const std = @import("std");
const time = @import("./time.zig");

const Character = @import("../constants.zig").Character;

const Debug = @This();

var instance: ?Logger = null;
var mutex: std.Thread.Mutex = .{};

pub const LoggerSettings = struct {
    utcCorrectionHours: i8 = -4,
    standaloneLogFilePath: ?[]const u8 = null,
    envLogSeverityLevel: SeverityLevel = .DEBUG,
};

pub const SeverityLevel = enum(u8) {
    DEBUG = 0,
    INFO = 1,
    WARNING = 2,
    ERROR = 3,
};

pub fn getInstance() !*Logger {
    if (instance) |*inst| {
        return inst;
    }

    return error.UnableToReturnDebugInstance;
}

pub fn log(comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        inst.log(level, fmt, args);
    }
}

pub fn init(allocator: std.mem.Allocator, settings: LoggerSettings) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) {
        return; // Already initialized
    }

    instance = Logger{
        .allocator = allocator,
        .utcCorrectionHours = if (@abs(settings.utcCorrectionHours) >= 23) -4 else settings.utcCorrectionHours,
        .logFile = if (settings.standaloneLogFilePath != null) try std.fs.cwd().createFile(settings.standaloneLogFilePath.?, .{}) else null,
    };
}

pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.logFile) |*file| {
            file.close();
        }

        if (inst.latestLog) |latestLog| {
            inst.allocator.free(latestLog);
            inst.latestLog = null;
        }
    }

    instance = null;
}

pub fn getLatestLog() [:0]const u8 {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.latestLog) |latestLog| {
            return latestLog;
        } else return "";
    } else return "";
}

pub const Logger = struct {
    allocator: std.mem.Allocator,
    utcCorrectionHours: i8 = -4,
    logFile: ?std.fs.File = null,
    latestLog: ?[:0]const u8 = null,

    pub fn log(self: *Logger, comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
        const t = time.now(self.utcCorrectionHours);

        const severityPrefix: [:0]const u8 = switch (level) {
            .DEBUG => "DEBUG",
            .INFO => "INFO",
            .WARNING => "WARNING",
            .ERROR => "ERROR",
        };

        // switch (level) {
        //     .DEBUG => {
        //         logFn = std.log.debug;
        //         severityPrefix = "DEBUG";
        //     },
        //     .INFO => {
        //         logFn = std.log.info;
        //         severityPrefix = "INFO";
        //     },
        //     .WARNING => {
        //         logFn = std.log.warn;
        //         severityPrefix = "WARNING";
        //     },
        //     .ERROR => {
        //         logFn = std.log.err;
        //         severityPrefix = "ERROR";
        //     },
        // }
        //
        // Create the full message with timestamp and format arguments
        const full_message = std.fmt.allocPrintSentinel(
            self.allocator,
            "[{d:0>2}/{d:0>2}/{d} {d:0>2}:{d:0>2}:{d:0>2}] {s}: " ++ fmt,
            .{
                t.month,
                t.day,
                t.year,
                t.hours,
                t.minutes,
                t.seconds,
                severityPrefix,
            } ++ args,
            Character.NULL,
        ) catch |err| {
            const msg = "\nlog(): ERROR occurred attempting to allocPrintSentinel msg: \n\t{s}\nError: {any}";
            std.log.err(msg, .{ fmt, err });
            return;
        };

        defer self.allocator.free(full_message);

        if (full_message.len < 1) return;

        switch (level) {
            .DEBUG => std.log.debug("{s}", .{full_message}),
            .INFO => std.log.info("{s}", .{full_message}),
            .WARNING => std.log.warn("{s}", .{full_message}),
            .ERROR => std.log.err("{s}", .{full_message}),
        }

        if (self.logFile != null) self.writeLogToFile("\n{s}", .{full_message});
    }

    pub fn writeLogToFile(self: *Logger, comptime msg: []const u8, args: anytype) void {
        var isError: bool = false;

        if (self.latestLog) |latestLog| {
            self.allocator.free(latestLog);
            self.latestLog = null;
        }

        const fmtStr = std.fmt.allocPrintSentinel(self.allocator, msg, args, Character.NULL) catch |err| blk: {
            std.log.err("\nLogger.log(): ERROR - failed to print via allocPrint. Aborting print early. Error msg: {any}", .{err});
            isError = true;
            break :blk "";
        };

        if (isError or fmtStr.len < 1) {
            self.allocator.free(fmtStr);
            return;
        }

        self.latestLog = fmtStr;

        if (self.logFile) |logFile| {
            _ = logFile.write(fmtStr) catch |err| {
                std.log.err("Error: Logger.log() caught error during writing. {any}", .{err});
            };
        }
    }
};
