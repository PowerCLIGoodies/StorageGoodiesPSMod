function Get-SGDatastoreMountInfo {
<#	.Description
	Get Datastore mount info (like, is datastore mounted on given host, is SCSI LUN attached, so on)

	.Example
	Get-Datastore mydatastore0 | Get-SGDatastoreMountInfo

	.Outputs
	PSCustomObject
#>
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCustomObject])]
	param (
		## Datastore object(s) for which to get datastore mount- and SCSI LUN state information
		[parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore[]]$Datastore
	) ## end param

	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "SystemFile","StorageDeviceInfo.ScsiLun"}

	process {
		foreach ($dstThisOne in $Datastore) {
			$viewThisDStore = Get-View -Id $dstThisOne.Id -Property Name, Host, Info
			## get the canonical names for all of the extents that comprise this datastore
			$arrDStoreExtentCanonicalNames = $viewThisDStore.Info.Vmfs.Extent | Foreach-Object {$_.DiskName}
			## if there are any hosts associated with this datastore (though, there always should be)
			if ($viewThisDStore.Host) {
				foreach ($oDatastoreHostMount in $viewThisDStore.Host) {
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
	Get-Datastore myOldDatastore0 | Dismount-SGDatastore -VMHost (Get-VMHost myhost0.dom.com, myhost1.dom.com)
	Unmounts the VMFS volume myOldDatastore0 from specified VMHosts

	.Example
	Get-Datastore myOldDatastore1 | Dismount-SGDatastore
	Unmounts the VMFS volume myOldDatastore1 from all VMHosts associated with the datastore

	.Outputs
	None
#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param (
		## One or more datastore objects to whose VMFS volumes to unmount
		[parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore[]]$Datastore,

		## VMHost(s) on which to unmount a VMFS volume; if non specified, will unmount the volume on all VMHosts that have it mounted
		[parameter(ParameterSetName="SelectedVMHosts")][VMware.VimAutomation.Types.VMHost[]]$VMHost
	) ## end param

	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "SystemFile"}

	process {
		## for each of the datastores
		foreach ($dstThisOne in $Datastore) {
			## if the datastore is actually mounted on any host
			if ($dstThisOne.ExtensionData.Host) {
				## the MoRefs of the HostSystems upon which to act
				$arrMoRefsOfHostSystemsForUnmount = if ($PSCmdlet.ParameterSetName -eq "SelectedVMHosts") {$VMHost | Foreach-Object {$_.Id}} else {$dstThisOne.ExtensionData.Host | Foreach-Object {$_.Key}}
				## get array of HostSystem Views from which to unmount datastore
				$arrViewsOfHostSystemsForUnmount = Get-View -Property $arrHostsystemViewPropertiesToGet -Id $arrMoRefsOfHostSystemsForUnmount

				foreach ($viewThisHost in $arrViewsOfHostSystemsForUnmount) {
					## actually do the unmount (if not WhatIf)
					if ($PSCmdlet.ShouldProcess("VMHost '$($viewThisHost.Name)'", "Dismount ('unmount') VMFS datastore '$($dstThisOne.Name)'")) {
						$viewStorageSysThisHost = Get-View $viewThisHost.ConfigManager.StorageSystem -Property $arrStorageSystemViewPropertiesToGet
						## add try/catch here?  and, return something here?
						$viewStorageSysThisHost.UnmountVmfsVolume($dstThisOne.ExtensionData.Info.vmfs.uuid)
					} ## end if
				} ## end foreach
			} ## end if
		} ## end foreach
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

	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "SystemFile","StorageDeviceInfo.ScsiLun"}

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
