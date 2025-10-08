// Thin helpers over the DiskArbitration framework used by the privileged
// helper to classify target disks before destructive operations.
// Currently exposes validation utilities that inspect CFDictionary metadata
// retrieved from `DADiskCopyDescription`.
// ------------------------------------------------------------------------
const std = @import("std");
const c = @import("../types.zig").c;
const DeviceType = @import("../types.zig").DeviceType;
const Debug = @import("../util/debug.zig");

/// Returns true when the Disk Arbitration dictionary marks the device as
/// internal. Returns an error when the key is missing or typed incorrectly.
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

/// Attempts to unmount all volumes on the specified BSD disk name. Returns
/// `true` if Disk Arbitration reported success, `false` otherwise.
pub fn requestUnmount(targetDisk: [:0]const u8, deviceType: DeviceType, statusResultPtr: *bool) !void {

    // TODO: perform a check to ensure the device has a kIOMediaRemovableKey key
    // TODO: refactor code to smalelr functions

    if (targetDisk.len < 2) return error.MALFORMED_TARGET_DISK_STRING;

    Debug.log(.INFO, "Received bsdName: {s}", .{targetDisk});

    // const bsdName = std.mem.sliceTo(targetDisk, 0x00);
    // Debug.log(.INFO, "Sliced bsdName: {s}", .{bsdName});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) return error.FAILED_TO_CREATE_DA_SESSION;
    defer c.CFRelease(daSession);

    Debug.log(.INFO, "Successfully started a blank DASession.", .{});

    const currentLoop = c.CFRunLoopGetCurrent();

    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    // Ensure unscheduling happens before the session is released
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    Debug.log(.INFO, "DASession is successfully scheduled with the run loop.", .{});

    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, targetDisk.ptr);

    if (daDiskRef == null) return error.FAILED_TO_CREATE_DA_DISK_REF;
    defer c.CFRelease(daDiskRef);

    Debug.log(.INFO, "DA Disk refererence is successfuly created for the provided device BSD name.", .{});

    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));

    if (diskInfo == null) return error.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    defer c.CFRelease(diskInfo);

    Debug.log(.INFO, "DA Disk Description is successfully obtained/copied.", .{});

    // _ = c.CFShow(diskInfo);

    if (try isTargetDiskInternalDevice(diskInfo)) {
        if (deviceType != .SD) return error.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;
    }

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{targetDisk});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, @ptrCast(statusResultPtr));

    c.CFRunLoopRun();
}

pub fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.c) void {
    if (context == null) {
        Debug.log(.ERROR, "Unmount callback invoked without context pointer.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
        return;
    }

    const unmountStatus: *bool = @ptrCast(context);
    Debug.log(.INFO, "Processing unmountDiskCallback()...", .{});

    const bsdNameCPtr: [*c]const u8 = c.DADiskGetBSDName(disk);
    const bsdName: [:0]const u8 = @ptrCast(std.mem.sliceTo(bsdNameCPtr, 0x00));

    if (bsdName.len == 0) {
        Debug.log(.WARNING, "unmountDiskCallback(): bsdName received is of 0 length.", .{});
    }

    if (dissenter != null) {
        Debug.log(.WARNING, "Disk Arbitration Dissenter returned a non-empty status.", .{});

        unmountStatus.* = false;
        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusString: [256]u8 = undefined;

        if (statusStringRef != null) {
            _ = c.CFStringGetCString(statusStringRef, &statusString, statusString.len, c.kCFStringEncodingUTF8);
        }

        Debug.log(.ERROR, "Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusString });
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    } else {
        unmountStatus.* = true;
        Debug.log(.INFO, "Successfully unmounted disk: {s}", .{bsdName});
        Debug.log(.INFO, "Finished unmounting all volumes for device.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}
