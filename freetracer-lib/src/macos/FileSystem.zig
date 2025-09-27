const std = @import("std");

pub fn unwrapUserHomePath(buffer: *[std.fs.max_path_bytes]u8, restOfPath: []const u8) ![]u8 {
    const userDir = std.posix.getenv("HOME") orelse return error.HomeEnvironmentVariableIsNULL;

    @memcpy(buffer[0..userDir.len], userDir);
    @memcpy(buffer[userDir.len .. userDir.len + restOfPath.len], restOfPath);

    return buffer[0 .. userDir.len + restOfPath.len];
}
