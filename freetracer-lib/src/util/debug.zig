//! Debug Manager - Thread-safe logging facade for GUI and helper applications
//!
//! Provides a comprehensive logging system with:
//! - Mutex-protected log formatting and output
//! - Optional file persistence with durability guarantees
//! - Timestamped severity-level filtering
//! - Integration with Zig's std.log for standard output
//!
//! Threading Model:
//! - All public functions are thread-safe via global mutex
//! - Callers should not hold locks during logging operations
//! - File I/O is serialized through mutex for consistency
//!
//! Memory Ownership:
//! - getLatestLog() returns a fresh allocation owned by caller
//! - Caller must free the returned memory
//! - Calling getLatestLog() again invalidates previous results
//! ==========================================================================
const std = @import("std");
const time = @import("./time.zig");
const Character = @import("../constants.zig").Character;

const Debug = @This();

var instance: ?Logger = null;
var mutex: std.Thread.Mutex = .{};

/// Maximum bytes per log message to prevent unbounded memory allocation
const MAX_LOG_MESSAGE_SIZE = 8192;

/// Valid UTC offset range: -12 to +14 hours
const MIN_UTC_OFFSET: i8 = -12;
const MAX_UTC_OFFSET: i8 = 14;

/// Configuration for logger initialization
pub const LoggerSettings = struct {
    /// UTC timezone offset in hours (-12 to +14). If out of range or null, uses system UTC
    utcCorrectionHours: ?i8 = null,

    /// Absolute path to log file for persistent logging. If null, logs only to stdout
    standaloneLogFilePath: ?[:0]const u8 = null,
};

/// Severity levels for log filtering (lower values = less important)
pub const SeverityLevel = enum(u8) {
    DEBUG = 0,
    INFO = 1,
    WARNING = 2,
    ERROR = 3,
};

/// Retrieves the logger singleton instance.
/// Must call init() before calling this function.
///
/// `Returns`: Pointer to the initialized Logger
/// `Errors`: UnableToReturnDebugInstance if logger not initialized
pub fn getInstance() !*Logger {
    if (instance) |*inst| {
        return inst;
    }

    return error.UnableToReturnDebugInstance;
}

/// Global logging function - thread-safe entry point for all logging.
/// Acquires mutex, validates logger is initialized, then formats and outputs the message.
///
/// `Arguments`:
///   level: Severity level controlling whether message is logged
///   fmt: Format string (comptime)
///   args: Format arguments
///
/// Note: This function never fails; errors are logged but not propagated
pub fn log(comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        inst.log(level, fmt, args);
    }
}

/// Initializes the logger singleton instance.
/// Must be called exactly once at application startup before any logging.
///
/// `Arguments`:
///   allocator: Memory allocator for log formatting and storage. Must remain valid for entire app lifetime.
///   settings: Configuration including UTC offset and optional log file path
///
/// `Errors`: None (silently succeeds if already initialized, logs warning instead)
pub fn init(allocator: std.mem.Allocator, settings: LoggerSettings) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) {
        std.log.warn("Debug logger already initialized; skipping reinit", .{});
        return;
    }

    // Validate and apply UTC offset with bounds checking
    const utcOffset = validateAndApplyUTCOffset(settings.utcCorrectionHours);

    // Open log file if path provided, with path validation
    var logFile: ?std.fs.File = null;
    if (settings.standaloneLogFilePath) |filePath| {
        logFile = openLogFile(filePath) catch |err| {
            std.log.err("Failed to open log file '{s}': {any}", .{ filePath, err });
            return err;
        };
    }

    instance = Logger{
        .allocator = allocator,
        .utcCorrectionHours = utcOffset,
        .logFile = logFile,
    };

    std.log.info("Debug logger initialized (UTC offset: {d}h, file logging: {})", .{ utcOffset, logFile != null });
}

/// Changes the minimum severity level for logging.
/// Messages below this level will not be logged.
///
/// `Arguments`:
///   newLevel: New minimum severity level
///
/// `Errors`: DebugLoggerIsNotInitialized if logger not initialized
pub fn setLoggingSeverity(newLevel: SeverityLevel) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        inst.currentSeverityLevel = newLevel;
    } else {
        return error.DebugLoggerIsNotInitialized;
    }
}

/// Cleans up logger resources and deinitializes singleton.
/// Must be called once at application shutdown.
/// All subsequent logging calls will be silently ignored.
pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        // Free latest log if present
        if (inst.latestLog) |latestLog| {
            inst.allocator.free(latestLog);
            inst.latestLog = null;
        }

        // Close log file with fsync for durability
        if (inst.logFile) |*file| {
            _ = file.sync() catch |err| {
                std.log.err("Failed to sync log file on deinit: {any}", .{err});
            };
            file.close();
        }
    }

    instance = null;
    std.log.info("Debug logger deinitialized", .{});
}

/// Retrieves the most recently logged message.
/// Returns a fresh allocation owned by the caller.
///
/// `Returns`: Latest log message (null-terminated), or empty string if no logs yet
/// `Note`: Caller must free the returned memory. Subsequent calls invalidate previous results.
pub fn getLatestLog() [:0]const u8 {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.latestLog) |latestLog| {
            const duplicated = inst.allocator.dupeZ(u8, latestLog) catch |err| {
                std.log.err("Failed to duplicate latest log: {any}", .{err});
                return "";
            };
            return duplicated;
        }
    }
    return "";
}

/// Converts severity level to human-readable string prefix.
/// `Returns`: Static string representation ("DEBUG", "INFO", "WARNING", "ERROR")
fn getSeverityPrefix(level: SeverityLevel) [:0]const u8 {
    return switch (level) {
        .DEBUG => "DEBUG",
        .INFO => "INFO",
        .WARNING => "WARNING",
        .ERROR => "ERROR",
    };
}

/// Validates and applies UTC offset with bounds checking.
/// Ensures offset is within valid range (-12 to +14 hours).
///
/// `Arguments`:
///   providedOffset: User-provided offset, or null to use system UTC
///
/// `Returns`: Valid UTC offset within acceptable range
fn validateAndApplyUTCOffset(providedOffset: ?i8) i8 {
    if (providedOffset) |offset| {
        if (offset >= MIN_UTC_OFFSET and offset <= MAX_UTC_OFFSET) {
            return offset;
        } else {
            std.log.warn("UTC offset {d} out of valid range ({d} to {d}); using system UTC", .{ offset, MIN_UTC_OFFSET, MAX_UTC_OFFSET });
            return time.getLocalUTCOffset();
        }
    }
    return time.getLocalUTCOffset();
}

/// Opens log file with validation.
/// Uses absolute path only; rejects relative paths to prevent directory traversal.
///
/// `Arguments`:
///   filePath: Path to log file (must be absolute path starting with /)
///
/// `Returns`: Opened file handle
/// `Errors`: FileOpenError if path is invalid or file cannot be opened
fn openLogFile(filePath: [:0]const u8) !std.fs.File {
    // Validate path is absolute and doesn't contain traversal sequences
    if (filePath.len == 0) {
        return error.InvalidPath;
    }

    if (filePath[0] != '/') {
        std.log.err("Log file path must be absolute (start with /): {s}", .{filePath});
        return error.InvalidPath;
    }

    if (std.mem.containsAtLeast(u8, filePath, 1, "..")) {
        std.log.err("Log file path contains directory traversal sequence: {s}", .{filePath});
        return error.InvalidPath;
    }

    // Extract directory and create it if needed
    if (std.fs.path.dirname(filePath)) |dirPath| {
        std.fs.makeDirAbsolute(dirPath) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                std.log.err("Failed to create log directory '{s}': {any}", .{ dirPath, err });
                return err;
            },
        };
    }

    // Create or open file for writing (truncate existing file)
    return std.fs.cwd().createFile(filePath, .{}) catch |err| {
        std.log.err("Failed to create log file '{s}': {any}", .{ filePath, err });
        return err;
    };
}

/// Logger implementation - handles actual formatting and output.
/// Contains the core logging logic accessed through the Debug public interface.
pub const Logger = struct {
    allocator: std.mem.Allocator,
    utcCorrectionHours: i8 = 0,
    logFile: ?std.fs.File = null,
    latestLog: ?[:0]const u8 = null,
    currentSeverityLevel: SeverityLevel = .INFO,

    /// Determines whether a message at the given severity should be logged.
    /// Higher severity levels always pass; lower levels filtered based on currentSeverityLevel.
    fn shouldLog(self: *const Logger, messageLevel: SeverityLevel) bool {
        return @intFromEnum(messageLevel) >= @intFromEnum(self.currentSeverityLevel);
    }

    /// Formats and outputs a log message.
    /// Adds timestamp, severity prefix, and formats message with provided arguments.
    /// If shouldLog() returns false, message is silently dropped.
    /// Both stdout and file logging (if configured) are performed.
    ///
    /// `Arguments`:
    ///   level: Severity level for filtering and prefix
    ///   fmt: Format string (comptime)
    ///   args: Format arguments
    ///
    /// `Note`: Never propagates errors; all failures logged but not reported to caller
    pub fn log(self: *Logger, comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
        // Check severity filter first before expensive operations
        if (!self.shouldLog(level)) {
            return;
        }

        const t = time.now();
        const severityPrefix = getSeverityPrefix(level);

        // Format complete message with timestamp and severity
        const fullMessage = std.fmt.allocPrintSentinel(
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
            std.log.err("Failed to format log message: {any}", .{err});
            return;
        };

        defer self.allocator.free(fullMessage);

        // Validate formatted message is not empty
        if (fullMessage.len < 1) {
            return;
        }

        // Output to standard logging system
        switch (level) {
            .DEBUG => std.log.debug("{s}", .{fullMessage}),
            .INFO => std.log.info("{s}", .{fullMessage}),
            .WARNING => std.log.warn("{s}", .{fullMessage}),
            .ERROR => std.log.err("{s}", .{fullMessage}),
        }

        // Write to file if configured
        if (self.logFile != null) {
            self.writeLogToFile("\n{s}", .{fullMessage});
        }
    }

    /// Writes a formatted message to the log file with durability guarantee.
    /// Stores message in latestLog for retrieval via getLatestLog().
    /// Validates all bytes were written and syncs to disk for crash safety.
    ///
    /// `Arguments`:
    ///   msg: Format string for file output
    ///   args: Format arguments
    ///
    /// `Note`: Errors are logged but not propagated
    pub fn writeLogToFile(self: *Logger, comptime msg: []const u8, args: anytype) void {
        // Format the message for file output
        const fmtStr = std.fmt.allocPrintSentinel(
            self.allocator,
            msg,
            args,
            Character.NULL,
        ) catch |err| {
            std.log.err("Failed to format log message for file: {any}", .{err});
            return;
        };

        // Validate formatted string is not empty
        if (fmtStr.len < 1) {
            self.allocator.free(fmtStr);
            return;
        }

        // Free and replace previous latest log
        if (self.latestLog) |latestLog| {
            self.allocator.free(latestLog);
        }
        self.latestLog = fmtStr;

        // Write to file with validation
        if (self.logFile) |logFile| {
            const bytesWritten = logFile.write(fmtStr) catch |err| {
                std.log.err("Failed to write to log file: {any}", .{err});
                return;
            };

            // Validate all bytes were written
            if (bytesWritten != fmtStr.len) {
                std.log.err("Log file write incomplete: wrote {d}/{d} bytes", .{ bytesWritten, fmtStr.len });
                return;
            }

            // Sync to disk for durability guarantee
            logFile.sync() catch |err| {
                std.log.err("Failed to sync log file: {any}", .{err});
                // Continue anyway; data is in kernel buffer even if sync failed
            };
        }
    }
};
