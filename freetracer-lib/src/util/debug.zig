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

pub fn init(allocator: std.mem.Allocator, utcCorrectionHours: i8) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) {
        return; // Already initialized
    }

    instance = Logger{
        .allocator = allocator,
        .utcCorrectionHours = if (@abs(utcCorrectionHours) >= 23) -4 else utcCorrectionHours,
    };
}

pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();

    instance = null;
}

pub const Logger = struct {
    allocator: std.mem.Allocator,
    utcCorrectionHours: i8 = -4,

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
            const msg = "\nlogError(): ERROR occurred attempting to allocPrintZ msg: \n\t{s}\nError: {any}";
            std.debug.print(msg, .{ fmt, err });
            Debug.log(.ERROR, msg, .{ fmt, err });
            break :blk "";
        };

        defer self.allocator.free(full_message);

        if (full_message.len < 1) return;

        if (logFn) |log_fn| {
            log_fn("{s}", .{full_message});
        }
    }
};
