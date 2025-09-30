const std = @import("std");
const c = @import("../types.zig").c;
const da = @import("../macos/DiskArbitration.zig");
const Debug = @import("../util/debug.zig");
const String = @import("./string.zig");

pub fn openDeviceValidated(bsdName: []const u8) !std.fs.File {
    if (bsdName.len < 2) return error.DeviceNameTooShort;
    if (bsdName.len > std.fs.max_name_bytes) return error.DeviceNameTooLong;

    const deviceDir = "/dev/";

    // Accept flat filename only (i.e. same level as directory)
    if (std.mem.count(u8, bsdName, "/") > 0) return error.DeviceBSDNameIsNotAFlatFilename;

    // Replace non-printable characters in the BSD name
    var sanitizedBuffer: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
    const sanitizedBsdName = String.sanitizeString(&sanitizedBuffer, bsdName);

    var unmountStatus: bool = false;

    // This performs a check via Disk Arbitration on whether or not the device is internal or removable
    try requestUnmount(sanitizedBsdName, &unmountStatus);

    while (!unmountStatus) std.Thread.sleep(500_000_000);

    // Open directory without following symlinks
    const directory = try std.fs.openDirAbsolute(deviceDir, .{ .no_follow = true });

    // _ = c.seteuid(0);

    // try std.posix.seteuid(0);

    // const uid = c.getuid();
    // const euid = c.geteuid();
    // Debug.log(.INFO, "UID: {}, EUID: {} (both should be 0)", .{ uid, euid });
    //
    // const path = "/dev/disk5";
    // const fd = c.open(path, c.O_RDONLY, @as(c_uint, 0));
    //
    // if (fd < 0) {
    //     const err_num = c.__error().*; // This gets errno on macOS
    //     const err_str = c.strerror(err_num);
    //     Debug.log(.ERROR, "open() failed with errno {}: {s}", .{ err_num, err_str });
    // } else {
    //     Debug.log(.INFO, "Successfully opened device, fd={}", .{fd});
    //     _ = c.close(fd);
    // }
    //
    const path = "/dev/disk5";
    const fd: c_int = c.open(path, c.O_RDWR, @as(c_uint, 0o644));

    if (fd == -1) {
        Debug.log(.ERROR, "fd is -1 :(", .{});
        const err_num = c.__error().*;
        const err_str = c.strerror(err_num);
        Debug.log(.ERROR, "open() failed with errno {}: {s}", .{ err_num, err_str });
        return error.UnableToOpenFileCSyscall;
    } else _ = c.close(fd);

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

pub fn requestUnmount(targetDisk: []const u8, statusResultPtr: *bool) !void {

    // TODO: perform a check to ensure the device has a kIOMediaRemovableKey key
    // TODO: refactor code to smalelr functions

    if (targetDisk.len < 2) return error.MALFORMED_TARGET_DISK_STRING;

    Debug.log(.INFO, "Received bsdName: {s}", .{targetDisk});

    const bsdName = std.mem.sliceTo(targetDisk, 0x00);

    Debug.log(.INFO, "Sliced bsdName: {s}", .{bsdName});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) return error.FAILED_TO_CREATE_DA_SESSION;
    defer c.CFRelease(daSession);

    Debug.log(.INFO, "Successfully started a blank DASession.", .{});

    const currentLoop = c.CFRunLoopGetCurrent();

    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    // Ensure unscheduling happens before the session is released
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

    if (try da.isTargetDiskInternalDevice(diskInfo)) return error.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, @ptrCast(statusResultPtr));

    c.CFRunLoopRun();
}

pub fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
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
    } else {
        unmountStatus.* = true;
        Debug.log(.INFO, "Successfully unmounted disk: {s}", .{bsdName});
        Debug.log(.INFO, "Finished unmounting all volumes for device.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}
