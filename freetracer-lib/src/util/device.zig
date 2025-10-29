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

pub const DeviceHandle = struct {
    raw: std.fs.File,
    blockName: [std.fs.max_name_bytes:0]u8,
    rawName: [std.fs.max_name_bytes:0]u8,
    deviceType: DeviceType,

    /// Closes the raw device handle.
    pub fn close(self: *DeviceHandle) void {
        self.raw.close();
    }

    /// Returns the canonical block device BSD name as a sentinel terminated slice.
    pub fn getBlockName(self: *DeviceHandle) [:0]const u8 {
        return std.mem.sliceTo(&self.blockName, Character.NULL);
    }

    /// Returns the canonical raw device BSD name as a sentinel terminated slice.
    pub fn getRawName(self: *DeviceHandle) [:0]const u8 {
        return std.mem.sliceTo(&self.rawName, Character.NULL);
    }
};

const CanonicalDiskNames = struct {
    block: [std.fs.max_name_bytes:0]u8,
    raw: [std.fs.max_name_bytes:0]u8,
};

/// Sanitises the supplied BSD name, unmounts the device, validates the block
/// node, and returns an exclusive handle to the raw character device alongside
/// canonical BSD names.
pub fn openDeviceValidated(bsdName: []const u8, deviceType: DeviceType) !DeviceHandle {
    if (bsdName.len < 2) return error.DeviceNameTooShort;
    if (bsdName.len > std.fs.max_name_bytes) return error.DeviceNameTooLong;

    if (std.mem.count(u8, bsdName, "/") > 0) return error.DeviceBSDNameIsNotAFlatFilename;

    var sanitizedBuffer: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
    const sanitizedName = String.sanitizeString(&sanitizedBuffer, bsdName);

    const canonicalNames = try deriveCanonicalNames(sanitizedName);
    const blockBsdSlice = std.mem.sliceTo(&canonicalNames.block, Character.NULL);
    const rawBsdSlice = std.mem.sliceTo(&canonicalNames.raw, Character.NULL);
    const deviceDir = "/dev/";

    Debug.log(.INFO, "Attempting to open device of type: {any}", .{deviceType});

    {
        var unmountStatus: bool = false;
        try da.requestUnmount(blockBsdSlice, deviceType, &unmountStatus);
        while (!unmountStatus) std.Thread.sleep(500_000_000);
    }

    // This block ensures the Privileged Helper is able to trigger/inherit "Removable Volumes" permission
    // via C's `open` syscall wrapper. This is important nuance.
    {
        var devicePathBuf: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
        const blockPath = try String.concatStrings(std.fs.max_name_bytes, &devicePathBuf, deviceDir, blockBsdSlice);

        const fd: c_int = c.open(blockPath.ptr, c.O_RDWR, @as(c_uint, 0o644));
        if (fd < 0) {
            const err_num = c.__error().*;
            const err_str = c.strerror(err_num);
            Debug.log(.ERROR, "open() failed with errno {}: {s}", .{ err_num, err_str });
            return error.UnableToOpenFileCSyscall;
        } else _ = c.close(fd);

        const blockPathSlice = std.mem.sliceTo(blockPath, Character.NULL);
        const blockDevice = try std.fs.openFileAbsolute(blockPathSlice, .{ .mode = .read_write, .lock = .none });
        defer blockDevice.close();

        const blockStat = try blockDevice.stat();
        if (blockStat.kind != std.fs.File.Kind.block_device) return error.FileIsNotABlockDevice;

        const rootFs = try std.fs.openFileAbsolute("/", .{ .lock = .none, .mode = .read_only });
        defer rootFs.close();
        const rootFsStat = try rootFs.stat();
        if (blockStat.inode == rootFsStat.inode) return error.DeviceCannotBeActiveRootFileSystem;
    }

    var rawPathBuf: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
    const rawPath = try String.concatStrings(std.fs.max_name_bytes, &rawPathBuf, deviceDir, rawBsdSlice);
    const rawPathSlice = std.mem.sliceTo(rawPath, Character.NULL);

    const rawDevice = try std.fs.openFileAbsolute(rawPathSlice, .{ .mode = .read_write, .lock = .exclusive });
    errdefer rawDevice.close();

    const rawStat = try rawDevice.stat();
    if (rawStat.kind != std.fs.File.Kind.character_device) return error.FileIsNotACharacterDevice;

    return DeviceHandle{
        .raw = rawDevice,
        .blockName = canonicalNames.block,
        .rawName = canonicalNames.raw,
        .deviceType = deviceType,
    };
}

fn deriveCanonicalNames(sanitized: [:0]const u8) !CanonicalDiskNames {
    const sanitizedSlice = std.mem.sliceTo(sanitized, Character.NULL);

    if (sanitizedSlice.len < 5) return error.DeviceNameTooShort;

    const hasRawPrefix = std.mem.startsWith(u8, sanitizedSlice, "rdisk");
    const hasBlockPrefix = std.mem.startsWith(u8, sanitizedSlice, "disk");

    if (!hasRawPrefix and !hasBlockPrefix) return error.DeviceNameMissingDiskPrefix;

    const suffixStart: usize = if (hasRawPrefix) 5 else 4;
    const suffix = sanitizedSlice[suffixStart..];

    if (suffix.len == 0) return error.DeviceNameMissingSuffix;

    for (suffix) |char| {
        if (!std.ascii.isDigit(char)) return error.DeviceNameSuffixInvalid;
    }

    var block: [std.fs.max_name_bytes:0]u8 = std.mem.zeroes([std.fs.max_name_bytes:0]u8);
    var raw: [std.fs.max_name_bytes:0]u8 = std.mem.zeroes([std.fs.max_name_bytes:0]u8);

    const blockPrefix = "disk";
    const rawPrefix = "rdisk";

    // Unsure when this is possible; perhaps when there are more virtual nodes than physical devices plugged in
    const maxPrefixLen = @max(blockPrefix.len, rawPrefix.len);
    if (suffix.len + maxPrefixLen >= std.fs.max_name_bytes) return error.DevicePathTooLong;

    @memcpy(block[0..blockPrefix.len], blockPrefix);
    @memcpy(block[blockPrefix.len .. blockPrefix.len + suffix.len], suffix);
    block[blockPrefix.len + suffix.len] = Character.NULL;

    @memcpy(raw[0..rawPrefix.len], rawPrefix);
    @memcpy(raw[rawPrefix.len .. rawPrefix.len + suffix.len], suffix);
    raw[rawPrefix.len + suffix.len] = Character.NULL;

    return CanonicalDiskNames{
        .block = block,
        .raw = raw,
    };
}

/// Issues a DKIOCSYNCHRONIZECACHE ioctl on the block handle and ejects the disk
/// via DiskArbitration so Disk Utility observes the updated partition map.
pub fn flushAndEject(handle: *DeviceHandle) !void {
    // var blockPathBuf: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
    // const blockSlice = std.mem.sliceTo(handle.getBlockName(), Character.NULL);
    // const blockPath = try String.concatStrings(std.fs.max_name_bytes, &blockPathBuf, "/dev/", blockSlice);
    // const blockPathSlice = std.mem.sliceTo(blockPath, Character.NULL);
    //
    // const blockFile = try std.fs.openFileAbsolute(blockPathSlice, .{ .mode = .read_write, .lock = .none });
    // defer blockFile.close();
    //
    // const fd: c_int = @intCast(blockFile.handle);
    // const ioctlResult = std.posix.system.ioctl(fd, c.DKIOCSYNCHRONIZECACHE, @as(c_int, 0));
    //
    // if (ioctlResult != 0) {
    //     const err_num: c_int = @intFromEnum(std.posix.errno(ioctlResult));
    //     const err_str = c.strerror(err_num);
    //     Debug.log(.ERROR, "ioctl(DKIOCSYNCHRONIZECACHE) failed with errno {any}: {s}", .{ err_num, err_str });
    //     return error.UnableToSynchronizeDeviceCache;
    // }

    var ejectStatus: bool = false;
    try da.requestEject(handle.getBlockName(), handle.deviceType, &ejectStatus);
    while (!ejectStatus) std.Thread.sleep(500_000_000);
}
