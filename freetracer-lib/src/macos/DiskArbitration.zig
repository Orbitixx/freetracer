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

    const bsdName = std.mem.sliceTo(targetDisk, 0x00);
    Debug.log(.INFO, "Initiating unmount for: {s}", .{targetDisk});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);
    if (daSession == null) return error.FAILED_TO_CREATE_DA_SESSION;
    defer c.CFRelease(daSession);

    Debug.log(.INFO, "Successfully started a blank DASession.", .{});

    const currentLoop = c.CFRunLoopGetCurrent();
    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    Debug.log(.INFO, "DASession is successfully scheduled with the run loop.", .{});

    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, bsdName.ptr);
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

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, @ptrCast(statusResultPtr));
    c.CFRunLoopRun();
}

/// Invokes DiskArbitration to eject the specified BSD disk. Returns once the
/// run loop callback has been processed.
pub fn requestEject(targetDisk: [:0]const u8, deviceType: DeviceType, statusResultPtr: *bool) !void {
    if (targetDisk.len < 2) return error.MALFORMED_TARGET_DISK_STRING;

    Debug.log(.INFO, "Received eject bsdName: {s}", .{targetDisk});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);
    if (daSession == null) return error.FAILED_TO_CREATE_DA_SESSION;
    defer c.CFRelease(daSession);

    const currentLoop = c.CFRunLoopGetCurrent();
    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, targetDisk.ptr);
    if (daDiskRef == null) return error.FAILED_TO_CREATE_DA_DISK_REF;
    defer c.CFRelease(daDiskRef);

    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));
    if (diskInfo == null) return error.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    defer c.CFRelease(diskInfo);

    if (try isTargetDiskInternalDevice(diskInfo)) {
        if (deviceType != .SD) return error.EJECT_REQUEST_ON_INTERNAL_DEVICE;
    }

    Debug.log(.INFO, "Eject request passed checks. Initiating eject call for disk: {s}.", .{targetDisk});

    c.DADiskEject(daDiskRef, c.kDADiskEjectOptionDefault, ejectDiskCallback, @ptrCast(statusResultPtr));
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
        var statusBuffer: [256:0]u8 = std.mem.zeroes([256:0]u8);
        var statusMessage: [:0]const u8 = "unavailable";

        if (statusStringRef != null) {
            const wroteCString = c.CFStringGetCString(statusStringRef, &statusBuffer, statusBuffer.len, c.kCFStringEncodingUTF8) != 0;
            if (wroteCString) statusMessage = statusBuffer[0..];
        }

        Debug.log(.ERROR, "Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusMessage });
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

pub fn ejectDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.c) void {
    if (context == null) {
        Debug.log(.ERROR, "Eject callback invoked without context pointer.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
        return;
    }

    const ejectStatus: *bool = @ptrCast(context);
    Debug.log(.INFO, "Processing ejectDiskCallback()...", .{});

    const bsdNameCPtr: [*c]const u8 = c.DADiskGetBSDName(disk);
    const bsdName: [:0]const u8 = @ptrCast(std.mem.sliceTo(bsdNameCPtr, 0x00));

    if (bsdName.len == 0) {
        Debug.log(.WARNING, "ejectDiskCallback(): bsdName received is of 0 length.", .{});
    }

    if (dissenter != null) {
        Debug.log(.WARNING, "Disk Arbitration Dissenter returned a non-empty status for eject.", .{});

        ejectStatus.* = false;
        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusBuffer: [256:0]u8 = std.mem.zeroes([256:0]u8);
        var statusMessage: [:0]const u8 = "unavailable";

        if (statusStringRef != null) {
            const wroteCString = c.CFStringGetCString(statusStringRef, &statusBuffer, statusBuffer.len, c.kCFStringEncodingUTF8) != 0;
            if (wroteCString) statusMessage = statusBuffer[0..];
        }

        Debug.log(.ERROR, "Failed to eject {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusMessage });
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    } else {
        ejectStatus.* = true;
        Debug.log(.INFO, "Successfully ejected disk: {s}", .{bsdName});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}
