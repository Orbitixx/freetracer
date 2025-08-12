const freetracer_lib = @import("freetracer-lib");

const ShutdownManager = @import("./managers/ShutdownManager.zig").ShutdownManagerSingleton;
const Debug = freetracer_lib.Debug;
const c = freetracer_lib.c;

fn isTargetDiskInternalDevice(diskDictionaryRef: c.CFDictionaryRef) bool {
    const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskDictionaryRef, c.kDADiskDescriptionDeviceInternalKey));

    if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
        Debug.log(.ERROR, "Failed to obtain internal device key boolean.", .{});
        ShutdownManager.terminateWithError(error.REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY);
        return true;
    }

    const isDeviceInternal: bool = (isInternalDeviceRef == c.kCFBooleanTrue);

    Debug.log(.INFO, "Finished checking for an internal device... isDeviceInternal: {any}", .{isDeviceInternal});

    return isDeviceInternal;
}
