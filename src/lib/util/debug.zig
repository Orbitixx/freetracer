const std = @import("std");
const Logger = @import("../../managers/GlobalLogger.zig").LoggerSingleton;

pub fn print(comptime msg: []const u8) void {
    std.debug.print(msg, .{});
    Logger.log(msg, .{});
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    Logger.log(fmt, args);
}
