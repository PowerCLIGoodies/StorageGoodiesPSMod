## ToDo Items for StorageGoodies PowerShell Module
- add `-VMHost` parameter to `Get-SGDatastoreMountInfo`, so as to be able to retrieve such mount/state information selectively instead of "for all VMHosts associated with this datastore"
- add `-RunAsync` parameter to `Disount-SGDatastore`, `Mount-SGDatastore` functions to allow for returning of tasks instead of running synchronously
- add return of a datastore mount info for functions `Disount-SGDatastore`, `Mount-SGDatastore`, for the sake of explicitness

