// High-level helpers for safely opening removable block devices on macOS.
// Provides sanitisation of BSD names, unmount orchestration via
// DiskArbitration, and guard rails against accessing the system root device.
// --------------------------------------------------------------------------
const std = @import("std");
const types = @import("../types.zig");
const c = types.c;
const da = @import("../macos/DiskArbitration.zig");
const Debug = @import("../util/debug.zig");
const String = @import("./string.zig");
const Character = @import("../constants.zig").Character;
const DeviceType = types.DeviceType;

/// Sanitises the supplied BSD name, unmounts the device, and returns a raw
/// block device handle opened with exclusive access.
pub fn openDeviceValidated(bsdName: []const u8, deviceType: DeviceType) !std.fs.File {
    if (bsdName.len < 2) return error.DeviceNameTooShort;
    if (bsdName.len > std.fs.max_name_bytes) return error.DeviceNameTooLong;

    const deviceDir = "/dev/";

    // Accept flat filename only (i.e. same level as directory)
    if (std.mem.count(u8, bsdName, "/") > 0) return error.DeviceBSDNameIsNotAFlatFilename;

    // Replace non-printable characters in the BSD name
    var sanitizedBuffer: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
    const sanitizedBsdName = String.sanitizeString(&sanitizedBuffer, bsdName);

    // Performs a check via Disk Arbitration on whether or not the device is internal or removable
    {
        var unmountStatus: bool = false;
        try da.requestUnmount(sanitizedBsdName, deviceType, &unmountStatus);
        while (!unmountStatus) std.Thread.sleep(500_000_000);
    }

    // This block ensures the Privileged Helper is able to trigger/inherit "Removable Volumes" permission
    // via C's `open` syscall wrapper. This is important nuance.
    {
        if (sanitizedBsdName.len >= std.fs.max_name_bytes + deviceDir.len) return error.DevicePathTooLong;

        // std.fs.max_name_bytes is used intentionally as /dev/diskN pattern names should be short by design
        var sanitizedDevicePathBuf: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
        const sanitizedDevicePath = try String.concatStrings(std.fs.max_name_bytes, &sanitizedDevicePathBuf, deviceDir, sanitizedBsdName);

        const fd: c_int = c.open(sanitizedDevicePath.ptr, c.O_RDWR, @as(c_uint, 0o644));

        if (fd < 0) {
            const err_num = c.__error().*;
            const err_str = c.strerror(err_num);
            Debug.log(.ERROR, "open() failed with errno {}: {s}", .{ err_num, err_str });
            return error.UnableToOpenFileCSyscall;
        } else _ = c.close(fd);
    }

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
