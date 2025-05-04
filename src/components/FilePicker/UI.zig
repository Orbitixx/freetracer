const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");
const UI = @import("../../lib/ui/ui.zig");
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const ResourceManager = @import("../../managers/ResourceManager.zig").ResourceManagerSingleton;

const Font = @import("../../managers/ResourceManager.zig").FONT;

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
bgRect: ?UI.Rectangle = null,
diskImage: ?rl.Texture2D = null,

pub fn init(self: *Self) void {
    self.bgRect = UI.Rectangle{ .x = relW(0.08), .y = relH(0.2), .w = relW(0.35), .h = relH(0.7) };

    self.button = UI.Button().init("SELECT ISO", 0, 0, 14, BUTTON_COLOR_VARIANTS);

    const btnX: f32 = self.bgRect.?.relW(0.5) - @divTrunc(self.button.?.rect.transform.w, @as(f32, 2.0));
    const btnY: f32 = self.bgRect.?.relH(0.9) - @divTrunc(self.button.?.rect.transform.h, @as(f32, 2.0));

    self.button.?.setPosition(btnX, btnY);
    self.button.?.hasShadow = true;
    self.diskImage = rl.loadTexture("/Users/cerberus/Documents/Projects/freetracer/src/resources/img/disk_image.png") catch unreachable;
}

pub fn update(self: *Self) void {
    if (self.button) |*button| {
        button.events();
        if (button.state == ButtonState.ACTIVE) self.appObserver.onNotify(AppObserverEvent.SELECT_ISO_BTN_CLICKED, .{});
    }
}

pub fn draw(self: Self) void {
    rl.drawRectangleRounded(self.bgRect.?.toRaylibRectangle(), 0.04, 0, .{ .r = 248, .g = 135, .b = 255, .a = 43 });
    rl.drawRectangleRoundedLinesEx(self.bgRect.?.toRaylibRectangle(), 0.04, 0, 2, .white);

    rl.drawTextEx(
        ResourceManager.getFont(Font.JERSEY10_REGULAR),
        "image",
        .{ .x = self.bgRect.?.relW(0.04), .y = self.bgRect.?.relH(0.01) },
        34,
        0,
        .white,
    );

    rl.drawTextureEx(self.diskImage.?, .{ .x = self.bgRect.?.relW(0.25), .y = self.bgRect.?.relH(0.3) }, 0, 1.0, .white);

    if (self.button) |button| button.draw();
}

const BUTTON_VARIANT_NORMAL: ButtonColorVariant = .{
    .rect = .{ .r = 115, .g = 102, .b = 162, .a = 255 },
    .text = .white,
};

const BUTTON_VARIANT_HOVER: ButtonColorVariant = .{
    .rect = .{ .r = 115, .g = 102, .b = 162, .a = 127 },
    .text = .white,
};

const BUTTON_VARIANT_ACTIVE: ButtonColorVariant = .{
    .rect = .{ .r = 96, .g = 83, .b = 145, .a = 255 },
    .text = .white,
};

const BUTTON_COLOR_VARIANTS: ButtonColorVariants = .{
    .normal = BUTTON_VARIANT_NORMAL,
    .hover = BUTTON_VARIANT_HOVER,
    .active = BUTTON_VARIANT_ACTIVE,
};
