const std = @import("std");
const env = @import("../../env.zig");

pub const LoggerSingleton = struct {
    var instance: ?Logger = null;
    var mutex: std.Thread.Mutex = .{};

    pub const Logger = struct {
        allocator: std.mem.Allocator,
        file: std.fs.File,
        latestLog: ?[:0]const u8,

        pub fn log(self: *Logger, comptime msg: []const u8, args: anytype) void {
            mutex.lock();
            errdefer mutex.unlock();
            defer mutex.unlock();

            var buffer: [512]u8 = undefined;

            if (self.latestLog != null) {
                self.allocator.free(self.latestLog.?);
                self.latestLog = null;
            }

            const fmtStr = std.fmt.bufPrint(&buffer, msg, args) catch blk: {
                std.log.err("Logger.log() failed to print to formatted string. Last message: {s}.", .{msg});
                break :blk "WARNING: BADLY_FORMATTED_STRING: " ++ msg;
            };

            const duped = self.allocator.dupeZ(u8, fmtStr) catch |err| {
                std.log.err("Logger.log() failed to allocate sentinel-terminated slice. Last message: {s}. Error: {any}.", .{ msg, err });
                return;
            };

            self.latestLog = duped;

            _ = self.file.write("\n") catch |err| {
                std.log.err("Error: Logger.log() unable to write am empty line into the log file. {any}.", .{err});
            };

            _ = self.file.write(fmtStr) catch |err| {
                std.log.err("Error: Logger.log() caught error during writing. {any}", .{err});
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator) !void {
        mutex.lock();
        defer mutex.unlock();

        instance = .{
            .allocator = allocator,
            .file = try std.fs.cwd().createFile(env.MAIN_APP_LOGS_PATH, .{}),
            .latestLog = null,
        };
    }

    pub fn log(comptime msg: []const u8, args: anytype) void {
        // mutex.lock();
        // defer mutex.unlock();

        if (instance != null) {
            instance.?.log(msg, args);
        } else std.log.err("Error: Attempted to call Logger.log() before Logger is initialized! Culprit: {s}", .{msg});
    }

    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*inst| {
            inst.file.close();

            if (inst.latestLog != null) {
                inst.allocator.free(inst.latestLog.?);
                inst.latestLog = null;
            }
        }

        instance = null;
    }

    pub fn getLatestLog() [:0]const u8 {
        mutex.lock();
        defer mutex.unlock();

        if (instance == null) return "";

        if (instance.?.latestLog == null) return "";

        return instance.?.latestLog.?;
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
