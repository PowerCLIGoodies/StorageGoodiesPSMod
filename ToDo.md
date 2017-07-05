## ToDo Items for StorageGoodies PowerShell Module
- add `-VMHost` parameter to `Get-SGDatastoreMountInfo`, so as to be able to retrieve such mount/state information selectively instead of only "for all VMHosts associated with this datastore"
- add `-RunAsync` parameter to `Dismount-SGDatastore`, `Mount-SGDatastore` functions to allow for returning of tasks instead of running synchronously
- add return of a datastore mount info for functions `Dismount-SGDatastore`, `Mount-SGDatastore`, for the sake of explicitness
- possibly: add ability to provide `-CanonicalName` parameter to `Get-SGDatastoreMountInfo` so as to get attached/detached information for just given SCSI LUN; or, add function like `Get-SGScsiLunInfo` that will provide such information (could then employ that in `Get-SGDatastoreMountInfo` function for getting LUN state information in uniform way)
