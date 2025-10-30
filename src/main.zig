//! Freetracer - Application Main Entry Point
//! ------------------------------------------------------------------------------
//! Free and open-source by Orbitixx, LLC (https://orbitixx.com)
//! https://github.com/Orbitixx/freetracer
//!
//! Serves as main entry point. Handles memory allocation strategy selection
//! and delegates to AppManager for the application lifecycle. Memory allocation
//! is determined at compile-time based on build mode for optimal performance in
//! both debug and release builds.
//! ==============================================================================

const std = @import("std");
const builtin = @import("builtin");
const AppManager = @import("managers/AppManager.zig");

/// Compile-time constant determining allocator strategy.
/// Set to true for Debug builds, false for Release builds (ReleaseSafe, ReleaseFast, ReleaseSmall).
const IS_DEBUG_MODE = builtin.mode == .Debug;

/// Application entry point.
/// Orchestrates the complete application lifecycle:
/// `Errors`:
///   Propagates any errors from AppManager initialization or application startup.
pub fn main() !void {
    // Select allocator at compile-time based on build mode.
    // This ensures zero runtime overhead and optimal memory management for each build type.
    var mainAllocator = comptime if (IS_DEBUG_MODE) finalAllocator: {
        const allocator = std.heap.DebugAllocator(.{ .thread_safe = true });
        break :finalAllocator allocator.init;
    } else finalAllocator: {
        break :finalAllocator std.heap.page_allocator;
    };

    // Cleanup phase: only active in debug mode to report memory leaks
    defer {
        if (IS_DEBUG_MODE) {
            _ = mainAllocator.detectLeaks();
            _ = mainAllocator.deinit();
        }
    }

    // Extract the allocator interface from the selected allocator type
    const allocator = if (IS_DEBUG_MODE) mainAllocator.allocator() else mainAllocator;

    // Initialize the AppManager singleton with the selected allocator
    try AppManager.init(allocator);

    // Start the application event loop (blocks until window close)
    AppManager.startApp() catch |err| {
        std.log.err("\nFreetracer encountered critical error: {any}.\n", .{err});
        return err;
    };
}
