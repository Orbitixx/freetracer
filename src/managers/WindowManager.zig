const std = @import("std");
const rl = @import("raylib");
const debug = @import("../lib/util/debug.zig");
const env = @import("../env.zig");

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

        self.width = @as(f32, @floatFromInt(mWidth)) * env.WINDOW_WIDTH_FACTOR;
        self.height = @as(f32, @floatFromInt(mHeight)) * env.WINDOW_HEIGHT_FACTOR;

        debug.printf("\nWINDOW INITIALIZED: {d}x{d}\n", .{ self.width, self.height });

        rl.setWindowSize(@as(i32, @intFromFloat(self.width)), @as(i32, @intFromFloat(self.height)));

        const newX: i32 = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(mWidth, 2))) - self.width / 2);
        const newY: i32 = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(mHeight, 2))) - self.height / 2);

        rl.setWindowPosition(newX, newY);

        rl.setTargetFPS(60);
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
            debug.print("\nError: Attempted to init() a WindowManager/Window instance despite one already initialized.");
            return WindowManagerError.WindowInstanceAlreadyExistsError;
        }

        instance = Window{};
        instance.?.init();
    }

    pub fn getWindowWidth() f32 {
        if (instance) |inst| return inst.width;

        debug.print("\nWarning: WindowManager.getWindowWidth() called but no Window instance exists.");
        return 0;
    }

    pub fn getWindowHeight() f32 {
        if (instance) |inst| return inst.height;

        debug.print("\nWarning: WindowManager.getWindowHeight() called but no Window instance exists.");
        return 0;
    }

    pub fn relW(x: f32) f32 {
        std.debug.assert(x > 0);
        if (instance) |inst| return inst.width * x;

        debug.print("\nWarning: attempted to obtain relative monitor width without a Window instance.");
        return 0;
    }

    pub fn relH(y: f32) f32 {
        std.debug.assert(y > 0);
        if (instance) |inst| return inst.height * y;

        debug.print("\nWarning: attempted to obtain relative monitor height without a Window instance.");
        return 0;
    }

    pub fn deinit() void {
        if (instance) |inst| return inst.deinit();

        debug.print("\nWarning: Attempted to deinit() a WindowManager/Window instance despite no instance being initialized.");
        return;
    }
};

pub const WindowManagerError = error{
    WindowInstanceAlreadyExistsError,
};
