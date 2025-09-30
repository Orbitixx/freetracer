const c = @import("../types.zig").c;
const Debug = @import("../util/debug.zig");

pub fn isTargetDiskInternalDevice(diskDictionaryRef: c.CFDictionaryRef) !bool {
    const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskDictionaryRef, c.kDADiskDescriptionDeviceInternalKey));

    if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
        Debug.log(.ERROR, "Failed to obtain internal device key boolean.", .{});
        return error.REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY;
    }

    const isDeviceInternal: bool = (isInternalDeviceRef == c.kCFBooleanTrue);

    Debug.log(.INFO, "Finished checking for an internal device... isDeviceInternal: {any}", .{isDeviceInternal});

    return isDeviceInternal;
}
