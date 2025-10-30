const std = @import("std");
const builtin = @import("builtin");
const env = @import("../env.zig");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const xpc = freetracer_lib.xpc;

const XPCService = freetracer_lib.Mach.XPCService;

/// Compile-time flag to enable memory leak detection in debug builds
const IS_DEBUG_MODE = builtin.mode == .Debug;

/// Allocator type selection based on build mode
/// In debug mode: DebugAllocator with thread-safe tracking
/// In release mode: Interface type for flexibility
const Allocator = if (IS_DEBUG_MODE) std.heap.DebugAllocator(.{ .thread_safe = true }) else std.mem.Allocator;

/// Graceful shutdown delay to allow logs to flush to disk before process exit (500 milliseconds)
const SHUTDOWN_DELAY_NS: u64 = 500_000_000;

/// Comprehensive error type for shutdown manager operations.
/// Distinguishes between initialization failures and resource cleanup errors.
pub const ShutdownError = error{
    /// Shutdown manager not initialized; must call init() first
    NotInitialized,

    /// Attempted to initialize shutdown manager when instance already exists
    AlreadyInitialized,
};

/// ShutdownManagerSingleton provides graceful shutdown and cleanup for the privileged helper launchd daemon.
///
/// Responsibilities:
/// - Manages singleton initialization state
/// - Coordinates XPC service, Debug manager, and allocator cleanup on shutdown
/// - Ensures resources are released in the correct order for safe process termination
///
/// Implementation notes:
/// - Uses singleton pattern to ensure single instance throughout application lifetime
/// - Cleanup order: XPC service → Debug logs → Allocator (debug mode only)
/// - Includes configurable delay before exit to allow async log flushing
/// - Thread-safe via global mutex protecting instance state
pub const ShutdownManagerSingleton = struct {
    var instance: ?ShutdownManager = null;
    var mutex: std.Thread.Mutex = .{};

    const ShutdownManager = struct {
        allocator: *Allocator,
        xpcService: *XPCService,
    };

    /// Initializes the shutdown manager singleton.
    /// Must be called exactly once during application startup before any shutdown operations.
    ///
    /// `Arguments`:
    ///   allocator: Memory allocator for managing helper resources (used for leak detection in debug mode)
    ///   xpcService: XPC service instance to be cleaned up during shutdown
    ///
    /// `Returns`: ShutdownError.AlreadyInitialized if init() called more than once
    pub fn init(allocator: *Allocator, xpcService: *XPCService) ShutdownError!void {
        mutex.lock();
        defer mutex.unlock();

        if (instance != null) {
            Debug.log(.ERROR, "ShutdownManager.init() called but instance already initialized", .{});
            return ShutdownError.AlreadyInitialized;
        }

        instance = ShutdownManager{
            .allocator = allocator,
            .xpcService = xpcService,
        };

        Debug.log(.INFO, "ShutdownManager: Singleton initialized", .{});
    }

    /// Performs cleanup in safe order when shutting down the helper.
    ///
    /// Cleanup sequence:
    /// 1. Deinitializes XPC service (stops message handling)
    /// 2. Deinitializes Debug manager (flushes pending logs to disk)
    /// 3. Detects memory leaks and deinitializes allocator (debug mode only)
    ///
    /// If instance is not initialized, logs warning and ensures Debug is still deinitialized.
    fn performShutdown() void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |inst| {
            // Deinitialize XPC service first to stop receiving messages
            inst.xpcService.deinit();

            // Deinitialize Debug system to flush any pending log messages
            Debug.deinit();

            // Memory cleanup in debug mode: detect leaks and deinitialize allocator
            if (IS_DEBUG_MODE) {
                _ = inst.allocator.detectLeaks();
                _ = inst.allocator.deinit();
            }
        } else {
            Debug.log(.WARNING, "ShutdownManager.performShutdown() called but instance not initialized", .{});
            Debug.deinit();
        }
    }

    /// Internal callback for dispatch_async_f to perform shutdown and exit.
    /// This function is invoked asynchronously on the main dispatch queue by exitSuccessfully()
    /// or terminateWithError(). It performs full cleanup and then terminates the process.
    /// `Safety`: The context parameter is unused but required by callconv(.c) signature for C interop.
    fn exitFunction(context: ?*anyopaque) callconv(.c) void {
        _ = context;
        performShutdown();
        std.process.exit(0);
    }

    /// Gracefully exits the helper after successful task completion.
    ///
    /// Logs the successful completion message, waits to allow async log flushing,
    /// then dispatches shutdown to the main queue and exits with status code 0.
    ///
    /// This function does not return; it always results in process termination.
    pub fn exitSuccessfully() void {
        Debug.log(.INFO, "Freetracer Helper successfully finished executing.", .{});

        // Allow Debug system time to flush logs  before shutdown
        std.Thread.sleep(SHUTDOWN_DELAY_NS);

        // Schedule exit on main dispatch queue to ensure clean XPC teardown
        xpc.dispatch_async_f(xpc.dispatch_get_main_queue(), null, &exitFunction);
    }

    /// Gracefully exits the helper after an error condition.
    ///
    /// Logs the error code, waits to allow log flushing, then dispatches shutdown
    /// to the main queue and exits with status code 0 (launchd will detect error via logs).
    ///
    /// `Arguments`:
    ///   err: The error that triggered shutdown (logged for debugging)
    ///
    /// This function does not return; it always results in process termination.
    pub fn terminateWithError(err: anyerror) void {
        Debug.log(.ERROR, "Freetracer Helper terminated with error: {any}", .{err});

        // Allow Debug system time to flush error logs asynchronously before shutdown
        std.Thread.sleep(SHUTDOWN_DELAY_NS);

        // Schedule exit on main dispatch queue to ensure clean XPC teardown
        xpc.dispatch_async_f(xpc.dispatch_get_main_queue(), null, &exitFunction);
    }
};
