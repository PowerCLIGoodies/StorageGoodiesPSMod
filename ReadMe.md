## StorageGoodies PowerShell module
The StorageGoodies PowerShell module contains several functions for managing datastores and SCSI LUNs in a VMware vSphere environement.  The module is an update on the collection of functions originally published by Alan Renouf of [virtu-al.net](http://virtu-al.net) fame back in Jan 2012 at [https://communities.vmware.com/docs/DOC-18008](https://communities.vmware.com/docs/DOC-18008).

Some of the updates include:
- `-WhatIf` support where appropriate
- expanded support for parameters-from-pipeline
- ability to get datastore/LUN info at a per-host level
- ability to mount/dismount datastores/LUNs at a per-host level, versus just at "all attached hosts" level
- ability to set a SCSILun to "detached" (dismounted) state by LUN canonical name (instead of just by datastore object)
- updated nouns in function names to correspond with the thing on which the function is acting (the SCSI LUN on some, instead of datastore)
- updated function names to use PowerShell approved verbs (using the approved `Mount`/`Dismount` verbs in place of the non-approved `Attach`/`Detach`/`Unmount` verbs)
- some various optimizations for increased speed in some areas
- built-in help for the cmdlets
- a fleshed out module structure with pertinent information for publishing to the [PowerShellGallery](https://powershellgallery.com)
- availability of the module from the [PowerShellGallery](https://powershellgallery.com) for ease of consumption/distribution

Other information:
- the functions have had various iterations and homes throughout the years, from the original "DOC" noted above, to a few threads in the VMware Technology Network ("VMTN") communities, to the [VMware PowerCLI-Example-Scripts](https://github.com/vmware/PowerCLI-Example-Scripts/) GitHub repo
- as a part of coupling updates of the module source with updates of the module in the PowerShellGallery, the functions are updated in the PowerCLIGoodies [StorageGoodiesPSMod](https://github.com/PowerCLIGoodies/StorageGoodiesPSMod) GitHub repository. The eventual intention is to update the aforementioned VMware community repo with information about the StorageGoodiesPSMod repo and availability of the module from the PowerShellGallery.