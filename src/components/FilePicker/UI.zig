const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");
const UI = @import("../../lib/ui/ui.zig");
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;

const FilePickerComponent = @import("Component.zig");
const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const AppObserverEvent = @import("../../observers/AppObserver.zig").Event;

const relW = WindowManager.relW;
const relH = WindowManager.relH;

const ButtonState = UI.ButtonState;
const ButtonColorVariants = UI.ButtonColorVariants;
const ButtonColorVariant = UI.ButtonColorVariant;

const Self = @This();

/// ComponentUI's focused state relative to other components
active: bool = false,
appObserver: *const AppObserver,
button: ?UI.Button() = null,
bgRect: ?rl.Rectangle = null,

pub fn init(self: *Self) void {
    self.bgRect = rl.Rectangle{ .x = relW(0.08), .y = relH(0.2), .width = relW(0.35), .height = relH(0.7) };

    const rectX1: f32 = self.bgRect.?.x;
    const rectX2: f32 = self.bgRect.?.x + self.bgRect.?.width;
    const rectY1: f32 = self.bgRect.?.y;
    const rectY2: f32 = self.bgRect.?.y + self.bgRect.?.height;

    self.button = UI.Button().init("SELECT ISO", 0, 0, 18, BUTTON_COLOR_VARIANTS);

    const btnX: f32 = @divTrunc(rectX1 + rectX2, @as(f32, 2.0)) - @divTrunc(self.button.?.rect.width, @as(f32, 2.0));
    const btnY: f32 = @divTrunc(rectY1 + rectY2, @as(f32, 2.0)) - @divTrunc(self.button.?.rect.height, @as(f32, 2.0));

    self.button.?.setPosition(btnX, btnY);
}

pub fn update(self: *Self) void {
    if (self.button) |*button| {
        button.events();
        if (button.state == ButtonState.ACTIVE) self.appObserver.onNotify(AppObserverEvent.SELECT_ISO_BTN_CLICKED, .{});
    }
}

pub fn draw(self: Self) void {
    rl.drawRectangleRounded(self.bgRect.?, 0.04, 0, .{ .r = 248, .g = 135, .b = 255, .a = 17 });
    rl.drawRectangleRoundedLinesEx(self.bgRect.?, 0.04, 0, 2, .white);

    if (self.button) |button| button.draw();
}

const BUTTON_VARIANT_NORMAL: ButtonColorVariant = .{
    .rect = .{ .r = 115, .g = 102, .b = 162, .a = 100 },
    .text = .white,
};

const BUTTON_VARIANT_HOVER: ButtonColorVariant = .{
    .rect = .{ .r = 115, .g = 102, .b = 162, .a = 50 },
    .text = .white,
};

const BUTTON_VARIANT_ACTIVE: ButtonColorVariant = .{
    .rect = .{ .r = 96, .g = 83, .b = 145, .a = 100 },
    .text = .white,
};

const BUTTON_COLOR_VARIANTS: ButtonColorVariants = .{
    .normal = BUTTON_VARIANT_NORMAL,
    .hover = BUTTON_VARIANT_HOVER,
    .active = BUTTON_VARIANT_ACTIVE,
};
