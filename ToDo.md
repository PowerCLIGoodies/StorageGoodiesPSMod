## ToDo Items for StorageGoodies PowerShell Module
- add `-RunAsync` parameter to `Dismount-SGDatastore`, `Mount-SGDatastore`, `Dismount-SGScsiLun`, and `Mount-SGScsiLun` functions to allow for returning of tasks instead of running synchronously
    - this should enable parallel mount/dismount processing when passing multiple datastores/LUNs at a time (as direct param value instead of by pipeline), as the underlying API methods for asynchronous actions support multiple UUIDs per operation as opposed to the corresponding synchronous methods
    - done for `Dismount-SGDatastore`
- minimize number of `Get-View` calls in functions, for sake of speed (get out of `foreach` statements)
- add return of a datastore/LUN mount info for functions `Dismount-SGDatastore`, `Mount-SGDatastore`, `Dismount-SGScsiLun`, and `Mount-SGScsiLun`, for the sake of explicitness (when not running asynchronously)
- possibly: add ability to provide `-CanonicalName` parameter to `Get-SGDatastoreMountInfo` so as to get attached/detached information for just given SCSI LUN; or, add function like `Get-SGScsiLunInfo` that will provide such information (could then employ that in `Get-SGDatastoreMountInfo` function for getting LUN state information in uniform way)
- add `.Links` to comment-based help for functions