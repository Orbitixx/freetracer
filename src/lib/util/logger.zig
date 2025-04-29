const std = @import("std");

pub const LoggerSingleton = struct {
    var instance: ?Logger = null;
    var allocator: ?std.mem.Allocator = null;

    pub const Logger = struct {
        latestLog: [:0]const u8,
        logWritten: bool = false,
        file: std.fs.File,

        pub fn log(self: *Logger, comptime msg: []const u8, args: anytype) void {
            var buffer: [256]u8 = undefined;

            if (self.logWritten) {
                allocator.?.free(self.latestLog);
                self.logWritten = false;
            }

            const fmtStr = std.fmt.bufPrint(&buffer, msg, args) catch |err| {
                std.log.err("Logger.log() failed to print to formatted string. Last message: {s}. Error: {any}.", .{ msg, err });
                return;
            };

            self.latestLog = allocator.?.dupeZ(u8, fmtStr) catch |err| {
                std.log.err("Logger.log() failed to allocate sentinel-terminated slice. Last message: {s}. Error: {any}.", .{ msg, err });
                return;
            };

            self.logWritten = true;

            _ = self.file.write("\n") catch |err| {
                std.log.err("Error: Logger.log() unable to write am empty line into the log file. {any}.", .{err});
            };

            _ = self.file.write(fmtStr) catch |err| {
                std.log.err("Error: Logger.log() caught error during writing. {any}", .{err});
            };
        }
    };

    pub fn init(_allocator: std.mem.Allocator) !void {
        instance = .{
            .file = try std.fs.cwd().createFile("/Users/cerberus/freetracer_logs.log", .{}),
            .latestLog = "",
        };

        allocator = _allocator;
    }

    pub fn log(comptime msg: []const u8, args: anytype) void {
        instance.?.log(msg, args);
    }

    pub fn deinit() void {
        instance.?.file.close();
        if (instance.?.logWritten) allocator.?.free(instance.?.latestLog);

        instance = null;
        allocator = null;
    }

    pub fn getLatestLog() [:0]const u8 {
        return instance.?.latestLog;
    }
};

pub fn toCString(allocator: std.mem.Allocator, string: []const u8) ![:0]const u8 {
    if (string.len == 0) return error.OriginalStringMustBeNonZeroLength;

    var cString: []u8 = allocator.alloc(u8, string.len + 1) catch |err| {
        std.log.err("\nERROR (toCString()): Failed to allocate heap memory for C string. Error message: {any}", .{err});
        return error.FailedToCreateCString;
    };

    for (0..string.len) |i| {
        cString[i] = string[i];
    }

    cString[string.len] = 0x00;

    const newString: [:0]const u8 = cString[0..cString.len :0];

    return newString;
}
