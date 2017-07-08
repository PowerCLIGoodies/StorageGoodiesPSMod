function Get-SGDatastoreMountInfo {
<#	.Description
	Get Datastore mount info (like, is datastore mounted on given host, is SCSI LUN attached, so on)

	.Example
	Get-Datastore mydatastore0 | Get-SGDatastoreMountInfo
	Get info about the datastore and associated SCSI LUN(s) for all VMHosts with which the datastore is associated

	.Example
	Get-Datastore mydatastore0 | Get-SGDatastoreMountInfo -VMHost (Get-VMHost myhost0.dom.com, myhost1.dom.com)
	Get info about the datastore and associated SCSI LUN(s) for just the given VMHosts

	.Outputs
	PSCustomObject
#>
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCustomObject])]
	param (
		## Datastore object(s) for which to get datastore mount- and SCSI LUN state information
		[parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore[]]$Datastore,

		## VMHost(s) for which to get datastore mount- and SCSI LUN state information for the given datastore; if non specified, will get info for all VMHosts with which the given datastore is associated
		[parameter(ParameterSetName="SelectedVMHosts")][VMware.VimAutomation.Types.VMHost[]]$VMHost
	) ## end param

	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "StorageDeviceInfo.ScsiLun"}

	process {
		foreach ($dstThisOne in $Datastore) {
			$viewThisDStore = Get-View -Id $dstThisOne.Id -Property Name, Host, Info
			## get the canonical names for all of the extents that comprise this datastore
			$arrDStoreExtentCanonicalNames = $viewThisDStore.Info.Vmfs.Extent | Foreach-Object {$_.DiskName}
			## if there are any hosts associated with this datastore (though, there always should be)
			if ($viewThisDStore.Host) {
				## the DatastoreHostMount objects of interest:  if -VMHost is specified, just the DatastoreHostMount objects for those VMHost(s); else, the DatastoreHostMount objects for all VMHosts associated with the given datastore
				$arrDatastoreHostMountOfInterest = if ($PSBoundParameters.ContainsKey("VMHost")) {$viewThisDStore.Host | Where-Object {$VMHost.Id -contains $_.Key}} else {$viewThisDStore.Host}
				foreach ($oDatastoreHostMount in $arrDatastoreHostMountOfInterest) {
					## get the HostSystem and StorageSystem Views
					$viewThisHost = Get-View $oDatastoreHostMount.Key -Property $arrHostsystemViewPropertiesToGet
					$viewStorageSys = Get-View $viewThisHost.ConfigManager.StorageSystem -Property $arrStorageSystemViewPropertiesToGet
					foreach ($oScsiLun in $viewStorageSys.StorageDeviceInfo.ScsiLun) {
						## if this SCSI LUN is part of the storage that makes up this datastore (if its canonical name is in the array of extent canonical names)
						if ($arrDStoreExtentCanonicalNames -contains $oScsiLun.canonicalName) {
							New-Object -Type PSObject -Property ([ordered]@{
								Datastore = $viewThisDStore.Name
								ExtentCanonicalName = $oScsiLun.canonicalName
								VMHost = $viewThisHost.Name
								Mounted = $oDatastoreHostMount.MountInfo.Mounted
								ScsiLunState = Switch ($oScsiLun.operationalState[0]) {
									"ok" {"Attached"; break}
									"off" {"Detached"; break}
									default {$oScsiLun.operationalstate[0]}
								} ## end switch
							}) ## end new-object
						} ## end if
					} ## end foreach
				} ## end foreach
			} ## end if
		} ## end foreach
	} ## end process
} ## end fn


function Dismount-SGDatastore {
<#	.Description
	Dismount ("unmount") VMFS volume(s) from VMHost(s)

	.Example
	Dismount-SGDatastore -RunAsync -Datastore (Get-Datastore -Name myOldDatastore_*)
	Unmount the given VMFS datastores most efficiently (least overhead):  per VMHost involved, there is just one invocation to unmount and all VMFS UUIDs are passed at that time (versus invoking one unmount call per VMFS UUID). And, a Task object is returned for each VMHost involved

	.Example
	Get-Datastore myOldDatastore0 | Dismount-SGDatastore -VMHost (Get-VMHost myhost0.dom.com, myhost1.dom.com)
	Unmounts the VMFS volume myOldDatastore0 from specified VMHosts

	.Example
	Get-Datastore myOldDatastore1 | Dismount-SGDatastore
	Unmounts, synchronously, the VMFS volume myOldDatastore1 from all VMHosts associated with the datastore

	.Outputs
	None for synchronous operations or a VMware.VimAutomation.Types.Task object, one per VMHost involved, for asynchronous operations
#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param (
		## One or more datastore objects to whose VMFS volumes to unmount
		[parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore[]]$Datastore,

		## VMHost(s) on which to unmount a VMFS volume; if non specified, will unmount the volume on all VMHosts that have it mounted
		[parameter(ParameterSetName="SelectedVMHosts")][VMware.VimAutomation.Types.VMHost[]]$VMHost,

		## Switch:  Run command asynchronously? If so, returns a Task object for the dismount operation, one per VMHost involved. Can potentially result in quicker operations, depending on the means in which function is invoked. See examples for more information
		[Switch]$RunAsync
	) ## end param

	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "SystemFile"}

	process {
		## overview:
		## determine, for each host, the datastores to dismount
		#    so, from $Datastore, get a mapping of HostSystem IDs -> datastores to dismount
		#    this is a hashtable of (hostsystem Id -> array of zero or more datastores) key/value pairs
		#    if $VMHost is specified, make hashtable w/ keys of $VMhost.Id property, values of $Datastore where $_.ExtensionData.Host.key -contains $thisHost.Id
		#    else, make hashtable w/ Keys of all of the $Datastore.ExtensionData.Host.key, and for each host key, values of $Datastore where $_.ExtensionData.Host.key -contains $thisHost.Id
		#  then, get view of all host systems, and foreach hostsystem (get the hoststoragesystem, then) {
		#    if runasync {UnmountVmfsVolumeEx_Task(<all VMFS UUIDs involved for this VMHost>)}
		#    else {foreach datastore for this VMHost, invoke UnmountVmfsVolume()}

		## the IDs of the VMHosts on which to unmount any datastore(s)
		$arrIDsOfHostSystemsForUnmount = if ($PSCmdlet.ParameterSetName -eq "SelectedVMHosts") {
			## if $VMHost was specified, use just those VMHosts' IDs
			$VMHost | Foreach-Object {$_.Id}
		} else {
			## else, use the unique host IDs (which are MoRefs .ToString()) of all of the VMHosts involved with all of the given datastores, per the datastores' Host property
			$Datastore | Foreach-Object {$_.ExtensionData.Host} | Foreach-Object {$_.Key} | Foreach-Object {$_.ToString()} | Sort-Object -Unique
		} ## end else
		## the hashtable of VMHostID -> (zero-or-more datastores upon which to act)
		$hshHostIdToDStoreToUnmount = @{}
		## foreach VMHost ID, get the datastores in $Datastore that are associated with said VMHost ID
		$arrIDsOfHostSystemsForUnmount | Foreach-Object {$strThisHostId = $_; $hshHostIdToDStoreToUnmount[$strThisHostId] = $Datastore | Where-Object {($_.ExtensionData.Host.Key | Foreach-Object {$_.ToString()}) -contains $strThisHostId}}

		## get view of all HostSystems and unmount the given datastores in the appropriate way (asynch or synch)
		Get-View -Id $hshHostIdToDStoreToUnmount.Keys -Property $arrHostsystemViewPropertiesToGet | Foreach-Object {
			## get the StorageSystem for this HostSystem, via which to invoke to appropriate Unmount method
			$viewThisHost = $_; $strThisHostId = $_.MoRef.ToString()
			$viewStorageSysThisHost = Get-View -Property $arrStorageSystemViewPropertiesToGet -Id $viewThisHost.ConfigManager.StorageSystem

			# if there is one or more datastore for this host, take action for this host (could be zero if caller specified a host that is not associated with the datastores specified)
			$intNumDStoreToUnmount_thisHost = ($hshHostIdToDStoreToUnmount[$strThisHostId] | Measure-Object).Count
			if ($intNumDStoreToUnmount_thisHost -gt 0) {
				## if the call was to run this asynchronously
				if ($RunAsync) {
					## action message to use for ShouldProcess/Verbose output information
					$strShouldProcess_actionMsg = "Dismount ('unmount') {0}VMFS datastore{1} asynchronously" -f $(
						if ($intNumDStoreToUnmount_thisHost -ne 1) {"$intNumDStoreToUnmount_thisHost ", "s"}
						else {"", " '$($hshHostIdToDStoreToUnmount[$strThisHostId].Name)'"}
					)
					## dismount all of the given datastores in one call for this hostsystem via UnmountVmfsVolumeEx_Task()
					if ($PSCmdlet.ShouldProcess("VMHost '$($viewThisHost.Name)'", $strShouldProcess_actionMsg)) {
						# call actual UnmountVmfsVolumeEx_Task() once with all of the VMFS UUIDs for the datastores for this host
						$oTaskMoref = $viewStorageSysThisHost.UnmountVmfsVolumeEx_Task($hshHostIdToDStoreToUnmount[$strThisHostId].ExtensionData.Info.Vmfs.Uuid)
						## return the Task object for this operation
						Get-Task -Id $oTaskMoref
					} ## end if
				} ## end if

				else {
					## for this hostsystem, foreach pertinent datastore to dismount (get from hashtable by hostsystem ID), dismount given VMFS UUID via UnmountVmfsVolume()
					$hshHostIdToDStoreToUnmount[$strThisHostId] | Foreach-Object {
						$dstThisOne = $_
						if ($PSCmdlet.ShouldProcess("VMHost '$($viewThisHost.Name)'", "Dismount ('unmount') VMFS datastore '$($dstThisOne.Name)'")) {
							## add try/catch here?  and, return something here?
							$viewStorageSysThisHost.UnmountVmfsVolume($dstThisOne.ExtensionData.Info.Vmfs.Uuid)
						} ## end if
					} ## end foreach-object
				} ## end else
			} ## end if
			## else, there were no datastores upon which to act for this VMHost
			else {Write-Verbose "No datastores in '-Datastore' parameter are associated with VMHost '$($viewThisHost.Name) -- taking no action for this VMHost'"}
		} ## end foreach-object (foreach hostsystem)
	} ## end process
} ## end fn


function Mount-SGDatastore {
<#	.Description
	Mount a VMFS volume on VMHost(s)

	.Example
	Get-Datastore myOldDatastore1 | Mount-SGDatastore
	Mounts the VMFS volume myOldDatastore1 on all VMHosts associated with the datastore (where it is not already mounted)

	.Example
	Get-Datastore myOldDatastore1 | Mount-SGDatastore -VMHost (Get-VMHost myhost0,myhost1)
	Mounts the VMFS volume myOldDatastore1 on the given VMHosts

	.Outputs
	None
#>
	[CmdletBinding(SupportsShouldProcess=$true)]
	param (
		## VMFS datastore object to mount on given VMHost(s)
		[parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore]$Datastore,

		## VMHost(s) on which to mount a VMFS volume; if non specified, will mount the volume on all VMHosts that are aware of the volume and that do not already have it mounted
		[parameter(ParameterSetName="SelectedVMHosts")][VMware.VimAutomation.Types.VMHost[]]$VMHost
	) ## end param

	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "SystemFile"}

	process {
		## foreach VMHost of interest, attach any of the desired SCSI LUNs that are not already attached
		$(if ($PSBoundParameters.ContainsKey("VMHost")) {Get-View -Id $VMHost.Id -Property $arrHostsystemViewPropertiesToGet}
		else {Get-View -Id ($Datastore.ExtensionData.Host | Foreach-Object {$_.Key}) -Property $arrHostsystemViewPropertiesToGet}) | Foreach-Object {
			$viewThisHost = $_
			## if this datastore is not already in "Mounted" state on this VMHost, mount it
			if (-not ($true -eq ($Datastore.ExtensionData.Host | Where-Object {$_.Key -eq $viewThisHost.MoRef}).MountInfo.Mounted)) {
				if ($PSCmdlet.ShouldProcess("VMHost '$($viewThisHost.Name)'", "Mount VMFS Datastore '$($Datastore.Name)'")) {
					$viewStorageSysThisHost = Get-View $viewThisHost.ConfigManager.StorageSystem -Property $arrStorageSystemViewPropertiesToGet
					$viewStorageSysThisHost.MountVmfsVolume($Datastore.ExtensionData.Info.vmfs.uuid)
				} ## end if
			} ## end if
			else {Write-Verbose -Verbose "Datastore '$($Datastore.Name)' already mounted on VMHost '$($viewThisHost.Name)'"}
		} ## end foreach-object
	} ## end process
} ## end fn


function Dismount-SGScsiLun {
	<#	.Description
		Dismount ("detach") SCSI LUN(s) from VMHost(s).  If specifying host, needs to be a VMHost object (as returned from Get-VMHost).  This was done to avoid any "matched host with similar name pattern" problems that may occur if accepting host-by-name.

		.Example
		Get-Datastore myOldDatastore0 | Dismount-SGScsiLun -VMHost (Get-VMHost myhost0.dom.com, myhost1.dom.com)
		Dismounts ("detaches") the SCSI LUN associated with datastore myOldDatastore0 from specified VMHosts

		.Example
		Dismount-SGScsiLun -VMHost (Get-VMHost myhost0.dom.com, myhost1.dom.com) -CanonicalName naa.60000970000192601761533037364335
		Dismounts ("detaches") the SCSI LUN associated with datastore myOldDatastore0 from specified VMHosts

		.Example
		Get-Datastore myOldDatastore1 | Dismount-SGScsiLun
		Dismounts ("detaches") the SCSI LUN associated with datastore myOldDatastore1 from all VMHosts associated with the datastore

		.Outputs
		None
	#>
	[CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ByDatastore",ConfirmImpact="High")]
	param (
		## One or more datastore objects to whose SCSI LUN to dismount ("detach")
		[Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="ByDatastore")][VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore[]]$Datastore,

		## One or more canonical name of SCSI LUN to dismount ("detach")
		[Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="ByCanonicalName")][string[]]$CanonicalName,

		## VMHost(s) on which to dismount ("detach") the SCSI LUN;
		#   when passing Datastore value, if VMHost specified, this will detach the SCSI LUN on all VMHosts that have it attached
		#   when passing CanonicalName value, VMHost is mandatory
		[Parameter(ParameterSetName="ByDatastore")][Parameter(Mandatory=$true,ParameterSetName="ByCanonicalName")][VMware.VimAutomation.Types.VMHost[]]$VMHost
	) ## end parm
	begin {
	} ## end begin

	process {
		Switch ($PSCmdlet.ParameterSetName) {
			"ByDatastore" {
				foreach ($dstThisOne in $Datastore) {
					## get the canonical names for all of the extents that comprise this datastore
					$arrDStoreExtentCanonicalNames = $dstThisOne.ExtensionData.Info.Vmfs.Extent | Foreach-Object {$_.DiskName}
					## if there are any hosts associated with this datastore (though, there always should be)
					if ($dstThisOne.ExtensionData.Host) {
						## the MoRefs of the HostSystems upon which to act
						$arrMoRefsOfHostSystemsForDetach = if ($PSBoundParameters.ContainsKey("VMHost")) {$VMHost | Foreach-Object {$_.Id}} else {$dstThisOne.ExtensionData.Host | Foreach-Object {$_.Key}}
						### call helper
						_Dismount-SGScsiLun_helper -HostSystemMoRef $arrMoRefsOfHostSystemsForDetach -DStoreExtentCanonicalName $arrDStoreExtentCanonicalNames
					} ## end if
				} ## end foreach
			} ## end case
			"ByCanonicalName" {
				$arrMoRefsOfHostSystemsForDetach = $VMHost | Foreach-Object {$_.Id}
				### call helper
				_Dismount-SGScsiLun_helper -HostSystemMoRef $arrMoRefsOfHostSystemsForDetach -DStoreExtentCanonicalName $CanonicalName
			} ## end case
		} ## end switch
	} ## end process
} ## end fn


function Mount-SGScsiLun {
	<#	.Description
		Mount ("attach") SCSI LUN(s) to VMHost(s)

		.Example
		Get-Datastore myOldDatastore1 | Mount-SGScsiLun
		Attaches the SCSI LUN associated with datastore myOldDatastore1 to all VMHosts associated with the datastore

		.Example
		Get-VMHost myhost0,myhost1 | Mount-SGScsiLun -CanonicalName naa.60000000000001,naa.60000000000002
		Attaches the given SCSI LUNs to the specified VMHosts

		.Outputs
		None
	#>
	[CmdletBinding(SupportsShouldProcess=$true)]
	param (
		## Datastore object whose SCSI LUN to mount ("attach")
		[Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="ByDatastore")][VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore]$Datastore,

		## VMHost(s) on which to mount ("attach") given SCSI LUN. If not specified, assumes that -Datastore value was provided, from which to determine the appropriate VMHosts
		[Parameter(Mandatory=$false,ValueFromPipeline=$true,ParameterSetName="ByDatastore")]
		[Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="ByLunCanonicalName")]
		[VMware.VimAutomation.Types.VMHost[]]$VMHost,

		## Canonical name(s) of LUN(s) to mount ("attach"). Expects value for -VMHost parameter, too
		[Parameter(Mandatory=$true,ParameterSetName="ByLunCanonicalName")][String[]]$CanonicalName
	) ## end param

	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "StorageDeviceInfo.ScsiLun"}

	process {
		## the canonical name(s) of the LUNs to attach
		$arrLunsToAttach_CanonicalNames = Switch ($PSCmdlet.ParameterSetName) {
			"ByDatastore" {
				$Datastore.ExtensionData.Info.Vmfs.Extent | Foreach-Object {$_.DiskName}
				break
				} ## end case
			"ByLunCanonicalName" {$CanonicalName} ## end case
		} ## end switch

		## foreach VMHost of interest, attach any of the desired SCSI LUNs that are not already attached
		$(if ($PSBoundParameters.ContainsKey("VMHost")) {Get-View -Id $VMHost.Id -Property $arrHostsystemViewPropertiesToGet}
		else {Get-View -Id ($Datastore.ExtensionData.Host | Foreach-Object {$_.Key}) -Property $arrHostsystemViewPropertiesToGet}) | Foreach-Object {
			## the HostSystem and StorageSystem Views
			$viewThisHost = $_
			$viewStorageSysThisHost = Get-View $viewThisHost.ConfigManager.StorageSystem -Property $arrStorageSystemViewPropertiesToGet
			foreach ($oScsiLun in $viewStorageSysThisHost.StorageDeviceInfo.ScsiLun) {
				## if this SCSI LUN is part of the storage that makes up this datastore (if its canonical name is in the array of extent canonical names)
				if ($arrLunsToAttach_CanonicalNames -contains $oScsiLun.canonicalName) {
					## if this SCSI LUN is not already attached
					if (-not ($oScsiLun.operationalState[0] -eq "ok")) {
						if ($PSCmdlet.ShouldProcess("VMHost '$($viewThisHost.Name)'", "Attach LUN '$($oScsiLun.CanonicalName)'")) {
							$viewStorageSysThisHost.AttachScsiLun($oScsiLun.Uuid)
						} ## end if
					} ## end if
					else {Write-Verbose -Verbose "SCSI LUN '$($oScsiLun.canonicalName)' already attached on VMHost '$($viewThisHost.Name)'"}
				} ## end if
			} ## end foreach
		} ## end foreach
	} ## end process
} ## end fn
