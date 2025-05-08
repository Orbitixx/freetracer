const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");
const UI = @import("../../lib/ui/ui.zig");
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const ResourceManager = @import("../../managers/ResourceManager.zig").ResourceManagerSingleton;

const Font = @import("../../managers/ResourceManager.zig").FONT;
const Texture = @import("../../managers/ResourceManager.zig").TEXTURE;

const ComponentID = @import("../Registry.zig").ComponentID;

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
active: bool = true,
appObserver: *const AppObserver,
button: ?UI.Button() = null,
bgRect: ?UI.Rectangle = null,
fileName: ?[:0]const u8 = null,

pub fn init(self: *Self) void {
    self.bgRect = UI.Rectangle{ .x = relW(0.08), .y = relH(0.2), .w = relW(0.35), .h = relH(0.7) };

    self.button = UI.Button().init("SELECT ISO", 0, 0, 14, BUTTON_COLOR_VARIANTS);

    const btnX: f32 = self.bgRect.?.relW(0.5) - @divTrunc(self.button.?.rect.transform.w, 2);
    const btnY: f32 = self.bgRect.?.relH(0.9) - @divTrunc(self.button.?.rect.transform.h, 2);

    self.button.?.setPosition(btnX, btnY);
    self.button.?.hasShadow = true;
}

pub fn update(self: *Self) void {
    if (self.button) |*button| {
        button.events();
        if (button.state == ButtonState.ACTIVE) self.appObserver.onNotify(AppObserverEvent.SELECT_ISO_BTN_CLICKED, .{});
    }
}

pub fn setActive(self: *Self, flag: bool) void {
    self.active = flag;

    switch (flag) {
        true => self.bgRect.?.w = relW(0.35),
        false => self.bgRect.?.w = relW(0.16),
    }
}

fn drawActive(self: *Self) void {

    // TODO: Does not need to be done every frame, refactor.
    self.bgRect.?.w = relW(0.35);

    rl.drawRectangleRounded(self.bgRect.?.toRaylibRectangle(), 0.04, 0, .{ .r = 248, .g = 135, .b = 255, .a = 43 });
    rl.drawRectangleRoundedLinesEx(self.bgRect.?.toRaylibRectangle(), 0.04, 0, 2, .white);

    rl.drawTextEx(
        ResourceManager.getFont(Font.JERSEY10_REGULAR),
        "image",
        .{ .x = self.bgRect.?.x + 12, .y = self.bgRect.?.relH(0.01) },
        34,
        0,
        .white,
    );

    rl.drawTextureEx(ResourceManager.getTexture(Texture.DISK_IMAGE), .{ .x = self.bgRect.?.relW(0.25), .y = self.bgRect.?.relH(0.3) }, 0, 1.0, .white);

    if (self.button) |button| button.draw();
}

fn drawInactive(self: *Self) void {

    // TODO: Does not need to be done every frame, refactor.
    self.bgRect.?.w = relW(0.16);

    rl.drawRectangleRounded(self.bgRect.?.toRaylibRectangle(), 0.04, 0, rl.Color.init(248, 135, 255, 20));
    rl.drawRectangleRoundedLinesEx(self.bgRect.?.toRaylibRectangle(), 0.04, 0, 2, rl.Color.init(248, 135, 255, 43));

    const comp: *FilePickerComponent = self.appObserver.getComponent(FilePickerComponent, ComponentID.ISOFilePicker);

    rl.drawTextEx(
        ResourceManager.getFont(Font.JERSEY10_REGULAR),
        "image",
        .{ .x = self.bgRect.?.x + 12, .y = self.bgRect.?.relH(0.01) },
        34,
        0,
        rl.Color.init(190, 190, 190, 255),
    );

    if (self.fileName == null) {
        const path: [:0]const u8 = comp.state.filePath orelse "No ISO selected...";
        var lastSlash: usize = 0;

        for (0..path.len) |i| {
            // Find the last forward slash in the path (0x2f)
            if (path[i] == 0x2f) lastSlash = i;
        }

        self.fileName = path[lastSlash + 1 .. path.len :0];
    }

    const textWidth: f32 = rl.measureTextEx(ResourceManager.getFont(Font.ROBOTO_REGULAR), self.fileName.?, 14, 0).x;
    const textWidthCorrection: f32 = textWidth / 2.0;

    rl.drawTextEx(
        ResourceManager.getFont(Font.ROBOTO_REGULAR),
        self.fileName.?,
        .{ .x = self.bgRect.?.relW(0.5) - textWidthCorrection, .y = self.bgRect.?.relH(0.7) },
        14,
        0,
        .white,
    );

    const diskTexture = ResourceManager.getTexture(Texture.DISK_IMAGE);
    const textureScale: f32 = 0.6;
    const textureWidth: f32 = @floatFromInt(diskTexture.width);
    const textureHeight: f32 = @floatFromInt(diskTexture.height);

    const widthCorrection: f32 = @divTrunc(textureWidth * textureScale, 2);
    const heightCorrection: f32 = @divTrunc(textureHeight * textureScale, 2);

    rl.drawTextureEx(
        diskTexture,
        .{ .x = self.bgRect.?.relW(0.5) - widthCorrection, .y = self.bgRect.?.relH(0.5) - heightCorrection },
        0,
        textureScale,
        rl.Color.init(255, 255, 255, 80),
    );
}

pub fn draw(self: *Self) void {
    if (self.active) self.drawActive() else self.drawInactive();
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

pub const BUTTON_COLOR_VARIANTS: ButtonColorVariants = .{
    .normal = BUTTON_VARIANT_NORMAL,
    .hover = BUTTON_VARIANT_HOVER,
    .active = BUTTON_VARIANT_ACTIVE,
};
