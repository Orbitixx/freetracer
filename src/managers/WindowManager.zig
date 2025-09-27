const std = @import("std");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;
const AppConfig = @import("../config.zig");

pub const Window = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,

    pub fn init(self: *Window) void {
        rl.initWindow(0, 0, "");

        const m = rl.getCurrentMonitor();
        const mWidth: i32 = rl.getMonitorWidth(m);
        const mHeight: i32 = rl.getMonitorHeight(m);

        self.width = @as(f32, @floatFromInt(mWidth)) * AppConfig.WINDOW_WIDTH_FACTOR;
        self.height = @as(f32, @floatFromInt(mHeight)) * AppConfig.WINDOW_HEIGHT_FACTOR;

        Debug.log(.INFO, "WINDOW INITIALIZED: {d}x{d}\n", .{ self.width, self.height });

        rl.setWindowSize(@as(i32, @intFromFloat(self.width)), @as(i32, @intFromFloat(self.height)));

        const newX: i32 = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(mWidth, 2))) - self.width / 2);
        const newY: i32 = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(mHeight, 2))) - self.height / 2);

        rl.setWindowPosition(newX, newY);

        rl.setTargetFPS(AppConfig.WINDOW_FPS);
    }

    pub fn deinit(self: Window) void {
        _ = self;
        rl.closeWindow();
    }
};

pub const WindowManagerSingleton = struct {
    var instance: ?Window = null;

    pub fn init() !void {
        if (instance != null) {
            Debug.log(.ERROR, "Attempted to init() a WindowManager/Window instance despite one already initialized.", .{});
            return WindowManagerError.WindowInstanceAlreadyExistsError;
        }

        instance = Window{};
        instance.?.init();
    }

    pub fn getWindowWidth() f32 {
        if (instance) |inst| return inst.width;

        Debug.log(.WARNING, "WindowManager.getWindowWidth() called but no Window instance exists.", .{});
        return 0;
    }

    pub fn getWindowHeight() f32 {
        if (instance) |inst| return inst.height;

        Debug.log(.WARNING, "WindowManager.getWindowHeight() called but no Window instance exists.", .{});
        return 0;
    }

    /// Determines absolute X position relative to the main window's dimensions
    pub fn relW(x: f32) f32 {
        std.debug.assert(x > 0);
        if (instance) |inst| return inst.width * x;

        Debug.log(.WARNING, "Attempted to obtain relative monitor width without a Window instance.", .{});
        return 0;
    }

    /// Determines absolute Y position relative to the main window's dimensions
    pub fn relH(y: f32) f32 {
        std.debug.assert(y > 0);
        if (instance) |inst| return inst.height * y;

        Debug.log(.WARNING, "Attempted to obtain relative monitor height without a Window instance.", .{});
        return 0;
    }

    pub fn deinit() void {
        if (instance) |inst| return inst.deinit();

        Debug.log(.WARNING, "Attempted to deinit() a WindowManager/Window instance despite no instance being initialized.", .{});
        return;
    }
};

pub const WindowManagerError = error{
    WindowInstanceAlreadyExistsError,
};
