const std = @import("std");
const time = @import("./time.zig");

const Debug = @This();

var instance: ?Logger = null;
var mutex: std.Thread.Mutex = .{};

pub const SeverityLevel = enum(u8) {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
};

pub fn log(comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        inst.log(level, fmt, args);
    }
}

pub fn init(allocator: std.mem.Allocator, utcCorrectionHours: i8, isLogFileEnabled: bool, logFilePath: ?[]const u8) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) {
        return; // Already initialized
    }

    if (isLogFileEnabled) {
        if (logFilePath == null) {
            std.log.err("Debug.Logger.init(): ERROR: logFilePath is NULL despite logFile flag being enabled!", .{});
            return error.DebugLoggerLogFilePathIsNull;
        }

        std.debug.assert(logFilePath != null);
    }

    instance = Logger{
        .allocator = allocator,
        .utcCorrectionHours = if (@abs(utcCorrectionHours) >= 23) -4 else utcCorrectionHours,
        .isLogFileEnabled = isLogFileEnabled,
        .logFile = if (isLogFileEnabled) try std.fs.cwd().createFile(logFilePath.?, .{}) else null,
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
    isLogFileEnabled: bool = true,
    logFile: ?std.fs.File = null,
    latestLog: ?[:0]const u8 = null,

    pub fn log(self: *Logger, comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
        const t = time.now(self.utcCorrectionHours);

        comptime var logFn: ?*const fn (comptime format: []const u8, args: anytype) void = null;
        comptime var severityPrefix: [:0]const u8 = "NONE";

        switch (level) {
            .DEBUG => {
                logFn = std.log.debug;
                severityPrefix = "DEBUG";
            },
            .INFO => {
                logFn = std.log.info;
                severityPrefix = "INFO";
            },
            .WARNING => {
                logFn = std.log.warn;
                severityPrefix = "WARNING";
            },
            .ERROR => {
                logFn = std.log.err;
                severityPrefix = "ERROR";
            },
        }

        // Create the full message with timestamp and format arguments
        const full_message = std.fmt.allocPrintZ(self.allocator, "[{d:0>2}/{d:0>2}/{d} {d:0>2}:{d:0>2}:{d:0>2}] {s}: " ++ fmt, .{
            t.month,
            t.day,
            t.year,
            t.hours,
            t.minutes,
            t.seconds,
            severityPrefix,
        } ++ args) catch |err| blk: {
            const msg = "\nlog(): ERROR occurred attempting to allocPrintZ msg: \n\t{s}\nError: {any}";
            std.debug.print(msg, .{ fmt, err });
            Debug.log(.ERROR, msg, .{ fmt, err });
            break :blk "";
        };

        defer self.allocator.free(full_message);

        if (full_message.len < 1) return;

        if (logFn) |log_fn| {
            log_fn("{s}", .{full_message});
        }

        if (self.isLogFileEnabled) self.writeLogToFile("{s}", .{full_message});
    }

    pub fn writeLogToFile(self: *Logger, comptime msg: []const u8, args: anytype) void {
        var isError: bool = false;

        if (self.latestLog) |latestLog| {
            self.allocator.free(latestLog);
            self.latestLog = null;
        }

        const fmtStr = std.fmt.allocPrintZ(self.allocator, msg, args) catch |err| blk: {
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
            std.log.info("Attempting to write log: {s}", .{fmtStr});

            _ = logFile.write(fmtStr) catch |err| {
                std.log.err("Error: Logger.log() caught error during writing. {any}", .{err});
            };
        }
    }
};
