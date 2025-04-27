const std = @import("std");

pub fn print(comptime msg: []const u8) void {
    std.debug.print(msg, .{});
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}
