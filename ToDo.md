## ToDo Items for StorageGoodies PowerShell Module
Items to definitely do:
- minimize number of `Get-View` calls in functions, for sake of speed (get out of `foreach` statements)
- add return for functions `Dismount-SGDatastore`, `Mount-SGDatastore`, `Dismount-SGScsiLun`, and `Mount-SGScsiLun`, for the sake of explicitness (when not running asynchronously)
    - maybe a datastore/LUN mount info object? Or, maybe a datastore/SCSILun, respectively
- add `.Links` to comment-based help for functions

Items to possibly do (not "certainly-to-do"):
- possibly: add ability to provide `-CanonicalName` parameter to `Get-SGDatastoreMountInfo` so as to get attached/detached information for just given SCSI LUN; or, add function like `Get-SGScsiLunInfo` that will provide such information (could then employ that in `Get-SGDatastoreMountInfo` function for getting LUN state information in uniform way)
- possibly (sometime in future?):  add `-RunAsync` parameter to `Mount-SGDatastore`, `Mount-SGScsiLun` functions to allow for returning of tasks instead of running synchronously
    - mounting datastore is not generally as slow as the related dismount action, so have not invested the time in adding async support to these two functions; have not confirmed potential speed increase for mounting SCSI LUN in parallel (async), yet
- consider add support for invoking `DeleteScsiLunState()` method on SCSI LUN canonical names. From help: "For previously detached SCSI Lun, remove the state information from host". This seems to deal with the list of detached SCSI LUNs for which an ESXi host keeps information until removed in some way, like through ESXCLI or possibly through this API method
