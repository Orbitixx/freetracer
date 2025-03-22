const std = @import("std");

pub fn print(comptime msg: []const u8) void {
    std.debug.print(msg, .{});
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

// fn printa(comptime msg: []const u8, comptime fmt: []const u8, value: anytype) void {
//
//     const maxLength = @max(std.mem.len(msg), 40); // Adjust 40 to a suitable maximum length
//     const padding = try std.mem.dupe(std.allocator.default, std.ascii.repeat(u8, maxLength - std.mem.len(msg)));
//     std.debug.print("{s}{s}\t" ++ fmt ++ "\n", .{ msg, padding, value });
// }
