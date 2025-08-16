const std = @import("std");
const env = @import("../env.zig");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

const c = freetracer_lib.c;

const ShutdownManager = @import("../managers/ShutdownManager.zig").ShutdownManagerSingleton;
const da = @import("./diskarbitration.zig");

const String = freetracer_lib.String;
const ReturnCode = freetracer_lib.HelperReturnCode;

pub fn openDeviceValidated(bsdName: []const u8) !std.fs.File {
    if (bsdName.len < 2) return error.DeviceNameTooShort;
    if (bsdName.len > std.fs.max_name_bytes) return error.DeviceNameTooLong;

    const deviceDir = "/dev/";

    // Accept flat filename only (i.e. same level as directory)
    if (std.mem.count(u8, bsdName, "/") > 0) return error.DeviceBSDNameIsNotAFlatFilename;

    // Replace non-printable characters in the BSD name
    var sanitizedBuffer: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
    const sanitizedBsdName = String.sanitizeString(&sanitizedBuffer, bsdName);

    // This performs a check via Disk Arbitration on whether or not the device is internal or removable
    const unmountResult = requestUnmountWithIORegistry(sanitizedBsdName);
    if (unmountResult != .SUCCESS) return error.UnableToUnmountDevice;

    // Open directory without following symlinks
    const directory = try std.fs.openDirAbsolute(deviceDir, .{ .no_follow = true });

    // Open device and ensure it's a block device and not a character device or another kind
    const device = try directory.openFile(sanitizedBsdName, .{ .mode = .read_write, .lock = .exclusive });
    errdefer device.close();
    const deviceStat = try device.stat();
    if (deviceStat.kind != std.fs.File.Kind.block_device) return error.FileIsNotABlockDevice;

    // Ensure device is not the same as the "/" root filesystem
    const rootFs = try std.fs.openFileAbsolute("/", .{ .lock = .none, .mode = .read_only });
    defer rootFs.close();
    const rootFsStat = try rootFs.stat();

    if (deviceStat.inode == rootFsStat.inode) return error.DeviceCannotBeActiveRootFileSystem;

    return device;
}

pub fn requestUnmountWithIORegistry(targetDisk: []const u8) ReturnCode {

    // TODO: perform a check to ensure the device has a kIOMediaRemovableKey key
    // TODO: refactor code to smalelr functions

    if (targetDisk.len < 2) return ReturnCode.MALFORMED_TARGET_DISK_STRING;

    Debug.log(.INFO, "Received bsdName: {s}", .{targetDisk});

    const bsdName = std.mem.sliceTo(targetDisk, 0x00);

    Debug.log(.INFO, "Sliced bsdName: {s}", .{bsdName});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) {
        Debug.log(.ERROR, "Failed to create DASession\n", .{});
        ShutdownManager.terminateWithError(error.REQUEST_DISK_UNMOUNT_FAILED_TO_CREATE_DA_DISK_SESSION);
        return ReturnCode.FAILED_TO_CREATE_DA_SESSION;
    }
    defer c.CFRelease(daSession);

    Debug.log(.INFO, "Successfully started a blank DASession.", .{});

    const currentLoop = c.CFRunLoopGetCurrent();

    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    // Ensure unscheduling happens before the session is released
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    Debug.log(.INFO, "DASession is successfully scheduled with the run loop.", .{});

    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, bsdName.ptr);

    if (daDiskRef == null) {
        Debug.log(.ERROR, "Could not create DADiskRef for '{s}', skipping.\n", .{bsdName});
        ShutdownManager.terminateWithError(error.REQUEST_DISK_UNMOUNT_FAILED_TO_CREATE_DA_DISK_REF);
        return ReturnCode.FAILED_TO_CREATE_DA_DISK_REF;
    }
    defer c.CFRelease(daDiskRef);

    Debug.log(.INFO, "DA Disk refererence is successfuly created for the provided device BSD name.", .{});

    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));

    if (diskInfo == null) {
        ShutdownManager.terminateWithError(error.REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_DISK_INFO_DICT_REF);
        return ReturnCode.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    }
    defer c.CFRelease(diskInfo);

    Debug.log(.INFO, "DA Disk Description is successfully obtained/copied.", .{});

    // _ = c.CFShow(diskInfo);

    if (da.isTargetDiskInternalDevice(diskInfo)) {
        Debug.log(.ERROR, "ERROR: internal device detected on disk: {s}. Aborting unmount operations for device.", .{bsdName});
        ShutdownManager.terminateWithError(error.REQUEST_DISK_UNMOUNT_UNMOUNT_REQUEST_ON_INTERNAL_DEVICE);
        return ReturnCode.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;
    }

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, null);

    c.CFRunLoopRun();

    return ReturnCode.SUCCESS;
}

pub fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    _ = context;

    Debug.log(.INFO, "Processing unmountDiskCallback()...", .{});

    const bsdNameCPtr: [*c]const u8 = c.DADiskGetBSDName(disk);
    const bsdName: [:0]const u8 = @ptrCast(std.mem.sliceTo(bsdNameCPtr, 0x00));

    if (bsdName.len == 0) {
        Debug.log(.WARNING, "unmountDiskCallback(): bsdName received is of 0 length.", .{});
    }

    if (dissenter != null) {
        Debug.log(.WARNING, "Disk Arbitration Dissenter returned a non-empty status.", .{});

        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusString: [256]u8 = undefined;

        if (statusStringRef != null) {
            _ = c.CFStringGetCString(statusStringRef, &statusString, statusString.len, c.kCFStringEncodingUTF8);
        }
        Debug.log(.ERROR, "Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusString });
    } else {
        Debug.log(.INFO, "Successfully unmounted disk: {s}", .{bsdName});

        Debug.log(.INFO, "Finished unmounting all volumes for device.", .{});

        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}
