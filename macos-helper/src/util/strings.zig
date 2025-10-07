const std = @import("std");
const env = @import("../env.zig");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

// Security caveat: ensure the received string is like "disk" or "rdisk"
pub fn isDiskStringValid(disk: []const u8) bool {

    // Ensure the length fits "diskX" at the very least (5 characters)
    if (disk.len < 5) {
        Debug.log(.ERROR, "isDiskStringValid(): disk identifier too short: {s}", .{disk});
        return false;
    }

    const isRawDisk: bool = disk.len >= 6 and std.mem.eql(u8, disk[0..5], "rdisk");

    // Capture the "disk" portion of "diskX"
    const isPrefixValid: bool = std.mem.eql(u8, disk[0..4], "disk") or (isRawDisk and std.mem.eql(u8, disk[0..5], "rdisk"));

    if (!isPrefixValid) {
        Debug.log(.ERROR, "isDiskStringValid(): invalid prefix in disk identifier: {s}", .{disk});
        return false;
    }

    const suffixSlice = if (isRawDisk) disk[5..] else disk[4..];
    if (suffixSlice.len == 0) {
        Debug.log(.ERROR, "isDiskStringValid(): missing suffix in disk identifier: {s}", .{disk});
        return false;
    }

    // Capture the "X" portion of "diskX"
    const suffix: u8 = std.fmt.parseInt(u8, suffixSlice, 10) catch |err| blk: {
        Debug.log(.ERROR, "isDiskStringValid(): unable to parse disk suffix, value: {s}. Error: {any}.", .{ disk, err });
        break :blk 0;
    };

    if (suffix == 0) return false;

    // Check if disk number is more than 1 (internal SSD) and under some unlikely arbitrary number like 100
    const isSuffixValid: bool = suffix > 1 and suffix < 100;

    return isSuffixValid;
}
