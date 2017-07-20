## ChangeLog for StorageGoodies PowerShell module

### v1.0.0
Initial release, updating from original iteration of functions from Jan 2012 by Alan Renouf and subsequently updated versions by the community at large.  Some of the juicy new features/enhancements:
| Category | Feature Detail |
|:--------:|----------------|
|new       | Added `-WhatIf` support where appropriate
|new       | Added `-RunAsync` parameter to `Dismount-SGDatastore` and `Dismount-SGScsiLun` functions to allow for returning of tasks instead of running synchronously. This enables parallel dismount processing when passing multiple datastores/LUNs at a time (as direct param value instead of by pipeline), as the underlying API methods for asynchronous actions support multiple UUIDs per operation as opposed to the corresponding synchronous methods
|improvement| Expanded support for parameters-from-pipeline, for more natural user experience
|new       | Added ability to get datastore/LUN info at a per-VMHost level (instead of just "for all VMHosts associated with this datsatore/LUN")
|new       | Added ability to mount/dismount datastores/LUNs at a per-VMHost level, versus just at "all attached VMHosts" level
|new       | Added ability to set a SCSILun to "detached" (dismounted) state by LUN canonical name (instead of just by datastore object)
|improvement       | Updated nouns in function names to correspond with the thing on which the function is acting (the SCSI LUN on some, instead of datastore)
|improvement       | Updated function names to use PowerShell approved verbs (using the approved `Mount`/`Dismount` verbs in place of the non-approved `Attach`/`Detach`/`Unmount` verbs)
|improvement       | Additional optimizations for increased speed in some areas
|new       | Added built-in help for the cmdlets
|improvement       | Fleshed out the module structure with pertinent information for publishing to the [PowerShellGallery](https://powershellgallery.com)
|new       | Provided availability of the module from the [PowerShellGallery](https://powershellgallery.com) for ease of consumption/distribution
