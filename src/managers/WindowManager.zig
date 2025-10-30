const std = @import("std");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;
const AppConfig = @import("../config.zig");
const ResourceManager = @import("./ResourceManager.zig").ResourceManagerSingleton;

/// Platform-specific macOS window drag-and-drop installation via Cocoa/NSWindow.
/// Called to enable drag-and-drop support on the native window handle.
/// Safety: Assumes win pointer is valid if non-null (validated by caller).
extern fn rl_drag_install_on_nswindow(win: ?*anyopaque) callconv(.c) void;

/// Minimum window width to ensure UI remains usable and visible
const MINIMUM_WINDOW_WIDTH: f32 = 864;

/// Minimum window height to ensure UI remains usable and visible
const MINIMUM_WINDOW_HEIGHT: f32 = 581;

/// Safely casts a floating-point value to an integer type with overflow checking.
/// Returns error if the value exceeds the target type's bounds.
fn safeCastFloatToInt(comptime IntType: type, value: f32) !IntType {
    const max_val: f32 = @floatFromInt(std.math.maxInt(IntType));
    const min_val: f32 = @floatFromInt(std.math.minInt(IntType));

    if (value > max_val or value < min_val) {
        return WindowError.DimensionOverflow;
    }

    return @intFromFloat(value);
}

/// Represents an application window with position and dimension tracking.
/// Manages window initialization, positioning, and lifecycle through raylib bindings.
pub const Window = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,

    /// Initializes the application window with calculated dimensions and centered positioning.
    ///
    /// Performs the following steps:
    /// 1. Creates the initial raylib window
    /// 2. Queries current monitor dimensions with validation
    /// 3. Calculates optimal window size based on monitor and config factors
    /// 4. Applies minimum dimension constraints
    /// 5. Validates window dimensions fit on monitor
    /// 6. Centers window on the current monitor
    /// 7. Installs platform-specific drag-and-drop support (macOS)
    /// 8. Configures frame rate and rendering
    ///
    /// Returns: WindowError if monitor dimensions are invalid, window handle is unavailable,
    ///          or computed dimensions overflow integer bounds.
    pub fn init(self: *Window) WindowError!void {
        rl.initWindow(0, 0, "Freetracer");

        // Query monitor information
        const monitor = rl.getCurrentMonitor();
        const monitorWidth: i32 = rl.getMonitorWidth(monitor);
        const monitorHeight: i32 = rl.getMonitorHeight(monitor);

        // Validate monitor dimensions to prevent invalid window creation
        if (monitorWidth <= 0 or monitorHeight <= 0) {
            Debug.log(.ERROR, "WindowManager: Invalid monitor dimensions: {d}x{d}", .{ monitorWidth, monitorHeight });
            return WindowError.InvalidMonitorDimensions;
        }

        const monitorWidthF: f32 = @floatFromInt(monitorWidth);
        const monitorHeightF: f32 = @floatFromInt(monitorHeight);

        Debug.log(.DEBUG, "WindowManager: Monitor dimensions: {d}x{d}", .{ monitorWidth, monitorHeight });

        // Calculate window dimensions with minimum constraints
        // Scale monitor dimensions by config factors, then apply minimums
        const scaledWidth: f32 = monitorWidthF * AppConfig.WINDOW_WIDTH_FACTOR;
        const scaledHeight: f32 = monitorHeightF * AppConfig.WINDOW_HEIGHT_FACTOR;

        self.width = @max(scaledWidth, MINIMUM_WINDOW_WIDTH);
        self.height = @max(scaledHeight, MINIMUM_WINDOW_HEIGHT);

        // Warn if calculated dimensions would exceed monitor bounds (with small margin for OS chrome)
        const margin: f32 = 50; // pixels for OS window chrome/taskbars
        if (self.width > monitorWidthF - margin or self.height > monitorHeightF - margin) {
            Debug.log(.WARNING, "WindowManager: Calculated window dimensions ({d}x{d}) may exceed monitor bounds", .{ self.width, self.height });
            self.width = @min(self.width, monitorWidthF - margin);
            self.height = @min(self.height, monitorHeightF - margin);
        }

        // Apply window size with safe casting to i32
        const windowWidthI32 = safeCastFloatToInt(i32, self.width) catch |err| {
            Debug.log(.ERROR, "WindowManager: Failed to cast window width {d}: {}", .{ self.width, err });
            return err;
        };
        const windowHeightI32 = safeCastFloatToInt(i32, self.height) catch |err| {
            Debug.log(.ERROR, "WindowManager: Failed to cast window height {d}: {}", .{ self.height, err });
            return err;
        };

        rl.setWindowSize(windowWidthI32, windowHeightI32);
        Debug.log(.INFO, "WindowManager: Window initialized at {d}x{d}", .{ self.width, self.height });

        // Center window on monitor using float arithmetic for precision, then cast
        const centerX: f32 = monitorWidthF / 2 - self.width / 2;
        const centerY: f32 = monitorHeightF / 2 - self.height / 2;

        const posX = safeCastFloatToInt(i32, centerX) catch 0;
        const posY = safeCastFloatToInt(i32, centerY) catch 0;

        rl.setWindowPosition(posX, posY);
        self.x = @floatFromInt(posX);
        self.y = @floatFromInt(posY);

        Debug.log(.DEBUG, "WindowManager: Window positioned at ({d}, {d})", .{ self.x, self.y });

        // Install platform-specific drag-and-drop support (macOS)
        const windowHandle = rl.getWindowHandle();
        if (@intFromPtr(windowHandle) == 0) {
            Debug.log(.ERROR, "WindowManager: Failed to obtain native window handle from raylib", .{});
            return WindowError.InvalidWindowHandle;
        }

        rl_drag_install_on_nswindow(windowHandle);

        // Configure rendering
        rl.setTargetFPS(AppConfig.WINDOW_FPS);
    }

    /// Gracefully closes and cleans up window resources through raylib.
    pub fn deinit(self: *Window) void {
        _ = self;
        rl.closeWindow();
        Debug.log(.DEBUG, "WindowManager: Window closed", .{});
    }
};

/// WindowManager singleton providing global access to window dimensions and utilities.
/// Ensures only one window instance exists throughout the application lifecycle.
pub const WindowManagerSingleton = struct {
    var instance: ?Window = null;

    /// Initializes the window manager and creates the main application window.
    /// Must be called exactly once before accessing any other WindowManager functions.
    ///
    /// Returns: WindowError.AlreadyInitialized if window already exists
    pub fn init() WindowError!void {
        if (instance != null) {
            Debug.log(.ERROR, "WindowManager.init() called but window instance already exists", .{});
            return WindowError.AlreadyInitialized;
        }

        instance = Window{};
        try instance.?.init();

        Debug.log(.INFO, "WindowManager: Singleton initialized", .{});
    }

    /// Returns the current window width in pixels.
    /// Logs a warning and returns 0 if window is not initialized.
    pub fn getWindowWidth() f32 {
        if (instance) |inst| return inst.width;

        Debug.log(.WARNING, "WindowManager.getWindowWidth() called but window not initialized", .{});
        return 0;
    }

    /// Returns the current window height in pixels.
    /// Logs a warning and returns 0 if window is not initialized.
    pub fn getWindowHeight() f32 {
        if (instance) |inst| return inst.height;

        Debug.log(.WARNING, "WindowManager.getWindowHeight() called but window not initialized", .{});
        return 0;
    }

    /// Calculates absolute X coordinate as a fraction of window width.
    /// Useful for responsive positioning: relativeWidth(0.5) returns center X.
    ///
    /// Arguments:
    ///   factor: Multiplier in range (0, 1] representing fraction of window width
    ///
    /// Returns: Absolute X position in pixels, or 0 if window not initialized
    /// Note: Asserts factor > 0 in debug builds; returns 0 for invalid input in release builds
    pub fn relativeWidth(factor: f32) f32 {
        if (factor <= 0) {
            Debug.log(.WARNING, "WindowManager.relativeWidth() called with invalid factor: {d}", .{factor});
            return 0;
        }

        if (instance) |inst| return inst.width * factor;

        Debug.log(.WARNING, "WindowManager.relativeWidth() called but window not initialized", .{});
        return 0;
    }

    /// Calculates absolute Y coordinate as a fraction of window height.
    /// Useful for responsive positioning: relativeHeight(0.5) returns center Y.
    ///
    /// Arguments:
    ///   factor: Multiplier in range (0, 1] representing fraction of window height
    ///
    /// Returns: Absolute Y position in pixels, or 0 if window not initialized
    /// Note: Asserts factor > 0 in debug builds; returns 0 for invalid input in release builds
    pub fn relativeHeight(factor: f32) f32 {
        if (factor <= 0) {
            Debug.log(.WARNING, "WindowManager.relativeHeight() called with invalid factor: {d}", .{factor});
            return 0;
        }

        if (instance) |inst| return inst.height * factor;

        Debug.log(.WARNING, "WindowManager.relativeHeight() called but window not initialized", .{});
        return 0;
    }

    /// Deprecated: Use relativeWidth() instead.
    /// Backward-compatible alias for existing code.
    pub fn relW(x: f32) f32 {
        return relativeWidth(x);
    }

    /// Deprecated: Use relativeHeight() instead.
    /// Backward-compatible alias for existing code.
    pub fn relH(y: f32) f32 {
        return relativeHeight(y);
    }

    /// Deinitializes the window manager and closes the application window.
    /// Logs a warning if no window instance exists.
    pub fn deinit() void {
        if (instance) |*inst| {
            inst.deinit();
            instance = null;
            Debug.log(.INFO, "WindowManager: Singleton deinitialized", .{});
            return;
        }

        Debug.log(.WARNING, "WindowManager.deinit() called but no window instance exists", .{});
    }
};

/// Comprehensive error type for window manager operations.
/// Distinguishes between initialization failures, dimension issues, and handle errors.
pub const WindowError = error{
    /// Attempted to initialize window manager when instance already exists
    AlreadyInitialized,

    /// Monitor returned invalid dimensions (zero or negative)
    InvalidMonitorDimensions,

    /// Computed window dimensions cannot be cast to i32 (overflow)
    DimensionOverflow,

    /// Failed to obtain native window handle from raylib
    InvalidWindowHandle,
};
