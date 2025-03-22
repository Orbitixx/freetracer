const std = @import("std");
const debug = @import("debug.zig");

pub fn write(comptime fmt: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print(fmt, args) catch |err| {
        debug.printf("\n:: ERROR: console.write caught an stdout.print error: {}", .{err});
    };

    try bw.flush() catch |err| {
        debug.printf("\n:: ERROR: console.write caught an std.io.bufferedWriter error in bw.flush(): {}", .{err});
    };
}
