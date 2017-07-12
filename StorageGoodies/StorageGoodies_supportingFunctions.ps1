function _Dismount-SGScsiLun_helper {
<#	.Description
	Helper function used internally by exported function to actually do the detach of the SCSI LUN
#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		## MoRefs of HostSystems from which to detach SCSI LUN
		[string[]]$HostSystemMoRef,
		## Canonical name of extent whose SCSI LUN to detach
		[string[]]$DStoreExtentCanonicalName
	)
	begin {$arrHostsystemViewPropertiesToGet = "Name","ConfigManager.StorageSystem"; $arrStorageSystemViewPropertiesToGet = "SystemFile","StorageDeviceInfo.ScsiLun"}
	process {
		## get array of HostSystem Views from which to detach SCSI LUN
		$arrViewsOfHostSystemsForDetach = Get-View -Property $arrHostsystemViewPropertiesToGet -Id $HostSystemMoRef

		foreach ($viewThisHost in $arrViewsOfHostSystemsForDetach) {
			## get the StorageSystem View
			$viewStorageSysThisHost = Get-View $viewThisHost.ConfigManager.StorageSystem -Property $arrStorageSystemViewPropertiesToGet
			foreach ($oScsiLun in $viewStorageSysThisHost.StorageDeviceInfo.ScsiLun) {
				## if this SCSI LUN is part of the storage that makes up this datastore (if its canonical name is in the array of extent canonical names)
				if ($DStoreExtentCanonicalName -contains $oScsiLun.canonicalName) {
					if ($PSCmdlet.ShouldProcess("VMHost '$($viewThisHost.Name)'", "Detach LUN '$($oScsiLun.CanonicalName)'")) {
						$viewStorageSysThisHost.DetachScsiLun($oScsiLun.Uuid)
					} ## end if
				} ## end if
			} ## end foreach
		} ## end foreach
	} ## end process
} ## end internal function
