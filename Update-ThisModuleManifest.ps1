<#	.Description
	Some code to help automate the updating of the ModuleManifest file
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param()
begin {
	$strModuleName = "StorageGoodies"
	## some code to generate the module manifest
	$strFilespecForPsd1 = "$PSScriptRoot\$strModuleName\${strModuleName}.psd1"

	$hshModManifestParams = @{
		# Confirm = $true
		Path = $strFilespecForPsd1
		ModuleVersion = "1.0.0"
		CompanyName = 'PowerCLIGoodies for the VMware PowerCLI community'
		Copyright = "MIT License"
		Description = "Module with functions for managing VMware datastores and SCSI LUNs"
		# AliasesToExport = @()
		FileList = Write-Output "${strModuleName}.psd1" "${strModuleName}Mod_functions.ps1" "en-US\about_${strModuleName}.help.txt"
		FunctionsToExport = Write-Output Get-DatastoreMountInfo
		IconUri = "https://avatars0.githubusercontent.com/u/10615837"
		LicenseUri = "https://github.com/PowerCLIGoodies/StorageGoodiesPSMod/blob/master/License"
		ProjectUri = "https://github.com/PowerCLIGoodies/StorageGoodiesPSMod"
		ReleaseNotes = "See release notes at https://github.com/PowerCLIGoodies/StorageGoodiesPSMod/blob/master/ChangeLog.md"
		RootModule = "${strModuleName}Mod_functions.ps1"
		Tags = Write-Output VMware vSphere PowerCLI Datastore Storage SCSI LUN Mount Dismount Attach Detach
		# Verbose = $true
	} ## end hashtable
} ## end begin

process {
	if ($PsCmdlet.ShouldProcess($strFilespecForPsd1, "Update module manifest")) {
		## do the actual module manifest update
		PowerShellGet\Update-ModuleManifest @hshModManifestParams
		## replace the comment in the resulting module manifest that includes "PSGet_" prefixed to the actual module name with a line without "PSGet_" in it
		(Get-Content -Path $strFilespecForPsd1 -Raw).Replace("# Module manifest for module 'PSGet_$strModuleName'", "# Module manifest for module '$strModuleName'") | Set-Content -Path $strFilespecForPsd1
	} ## end if
} ## end prcoess
