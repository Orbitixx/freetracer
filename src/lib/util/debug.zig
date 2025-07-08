const std = @import("std");
const env = @import("../../env.zig");
const time = @import("./time.zig");

const Logger = @import("../../managers/GlobalLogger.zig").LoggerSingleton;

const DebugSingleton = @This();

var instance: ?DebugInstance = null;
var mutex: std.Thread.Mutex = .{};

pub const LogSeverity = enum(u8) {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    FATAL_ERROR,
};

pub fn init(allocator: std.mem.Allocator) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) {
        const msg = "Error: attempted to re-initialize an existing DebugInstance singleton.";
        std.debug.print(msg, .{});
        std.log.err(msg, .{});
        return error.FailedToInitializeAnAlreadyInitializedDebugInstanceSingleton;
    }

    instance = DebugInstance{
        .allocator = allocator,
    };
}

const DebugInstance = struct {
    allocator: std.mem.Allocator,

    pub fn print(self: *DebugInstance, severity: LogSeverity, comptime fmt: []const u8, args: anytype) void {
        const t = time.now();

        // Create the full message with timestamp and format arguments in one step
        const full_message = std.fmt.allocPrintZ(self.allocator, "\n[{d:0>2}/{d:0>2}/{d} {d:0>2}:{d:0>2}:{d:0>2}] " ++ fmt, .{
            t.month,
            t.day,
            t.year,
            t.hours,
            t.minutes,
            t.seconds,
        } ++ args) catch |err| blk: {
            const msg = "\nDebug.print(): ERROR occurred attempting to allocPrintZ msg: \n\t{s}\nError: {any}";
            std.debug.print(msg, .{ fmt, err });
            break :blk "";
        };

        defer self.allocator.free(full_message);

        if (full_message.len < 1) return;

        if (@intFromEnum(severity) > env.DEBUG_SEVERITY) {
            std.debug.print("{s}", .{full_message});
        }
        Logger.log("{s}", .{full_message});
    }
};

pub fn print(comptime msg: []const u8) void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        inst.print(.WARNING, msg, .{});
    } else {
        const err = "\nDebug.print(): ERROR - attempted to print without a DebugInstance instantiated! Attempted to print: \n\t{s}";
        std.debug.print(err, .{msg});
        std.log.err(err, .{msg});
        return;
    }
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    if (instance) |*inst| {
        inst.print(.WARNING, fmt, args);
    } else {
        const err = "\nDebug.printf(): ERROR - attempted to print without a DebugInstance instantiated! Attempted to print: \n\t{s}";
        std.debug.print(err, .{fmt});
        std.log.err(err, .{fmt});
        return;
    }
}

pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();

    instance = null;
}
