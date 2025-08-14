const std = @import("std");
const env = @import("../env.zig");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

// Security caveat: ensure the received string is like "disk" or "rdisk"
pub fn isDiskStringValid(disk: []const u8) bool {

    // Ensure the length fits "diskX" at the very least (5 characters)
    std.debug.assert(disk.len >= 5);

    const isRawDisk: bool = std.mem.eql(u8, disk[0..5], "rdisk");

    // Capture the "disk" portion of "diskX"
    const isPrefixValid: bool = std.mem.eql(u8, disk[0..4], "disk") or std.mem.eql(u8, disk[0..5], "rdisk");

    // Debug.log(.DEBUG, "disk[0..4]: {s}, disk[0..5]: {s}", .{ disk[0..4], disk[0..5] });

    // Capture the "X" portion of "diskX"
    const suffix: u8 = std.fmt.parseInt(u8, if (isRawDisk) disk[5..disk.len] else disk[4..disk.len], 10) catch |err| blk: {
        Debug.log(.ERROR, "isDiskStringValid(): unable to parse disk suffix, value: {s}. Error: {any}.", .{ disk, err });
        break :blk 0;
    };

    // Check if disk number is more than 1 (internal SSD) and under some unlikely arbitrary number like 100
    const isSuffixValid: bool = suffix > 1 and suffix < 100;

    return isPrefixValid and isSuffixValid;
}
