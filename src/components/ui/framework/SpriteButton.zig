const std = @import("std");
const rl = @import("raylib");

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElementCallbacks = UIFramework.UIElementCallbacks;

const Styles = @import("../Styles.zig");
const Color = Styles.Color;

const ResourceImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceImport.ResourceManagerSingleton;
const TextureResource = ResourceImport.TextureResource;
const FontResource = ResourceImport.FONT;

const SpriteButton = @This();

const MAX_TEXT_LENGTH = 64;

pub const ButtonState = enum {
    Normal,
    Hover,
    Active,
    Disabled,
};

// pub const ClickHandler = struct {
//     function: *const fn (ctx: *anyopaque) void,
//     context: *anyopaque,
//
//     pub fn call(self: ClickHandler) void {
//         self.function(self.context);
//     }
// };
//
// pub const Callbacks = struct {
//     onClick: ?ClickHandler = null,
// };

pub const Style = struct {
    font: FontResource = .ROBOTO_REGULAR,
    fontSize: f32 = 24,
    spacing: f32 = 0,

    textColor: rl.Color = Color.white,
    hoverTextColor: rl.Color = Color.white,
    activeTextColor: rl.Color = Color.white,
    disabledTextColor: rl.Color = Color.lightGray,

    tint: rl.Color = Color.white,
    hoverTint: rl.Color = Color.themeSecondary,
    activeTint: rl.Color = Color.themePrimary,
    disabledTint: rl.Color = Color.transparentDark,

    textOffset: rl.Vector2 = .{ .x = 0, .y = 0 },
};

pub const Config = struct {
    identifier: ?UIElementIdentifier = null,
    text: []const u8,
    texture: TextureResource,
    style: Style = .{},
    callbacks: UIElementCallbacks = .{},
    enabled: bool = true,
};

identifier: ?UIElementIdentifier = null,
transform: Transform = .{},
style: Style = .{},
texture: rl.Texture2D,
font: rl.Font,
sourceRect: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

textBuffer: [MAX_TEXT_LENGTH:0]u8 = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8),
textSize: rl.Vector2 = .{ .x = 0, .y = 0 },
textPosition: rl.Vector2 = .{ .x = 0, .y = 0 },

state: ButtonState = .Normal,
/// True: the element is visible and interactible
/// False: the element is visible but not interactible
enabled: bool = true,
/// True: the element is visible and processing updates
/// False: the element is not visible and is not processing updates
active: bool = true,

cursorActive: bool = false,
layoutDirty: bool = true,
lastRect: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

callbacks: UIElementCallbacks = .{},

pub fn init(config: Config) SpriteButton {
    var buffer = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8);
    const capped = if (config.text.len >= MAX_TEXT_LENGTH) MAX_TEXT_LENGTH - 1 else config.text.len;
    @memcpy(buffer[0..capped], config.text[0..capped]);
    buffer[capped] = 0;

    const font = ResourceManager.getFont(config.style.font);
    const texture = ResourceManager.getTexture(config.texture);

    return .{
        .identifier = config.identifier,
        .style = config.style,
        .callbacks = config.callbacks,
        .texture = texture,
        .font = font,
        .textBuffer = buffer,
        .state = if (config.enabled) .Normal else .Disabled,
        .enabled = config.enabled,
    };
}

pub fn start(self: *SpriteButton) !void {
    self.transform.resolve();
    self.sourceRect = .{ .x = 0, .y = 0, .width = @floatFromInt(self.texture.width), .height = @floatFromInt(self.texture.height) };
    self.updateLayout();
}

pub fn update(self: *SpriteButton) !void {
    if (!self.active) return;
    self.transform.resolve();

    const rect = self.transform.asRaylibRectangle();
    const mouse = rl.getMousePosition();
    const hover = rl.checkCollisionPointRec(mouse, rect);
    const wantsCursor = hover and self.enabled;

    if (wantsCursor and !self.cursorActive) {
        rl.setMouseCursor(.pointing_hand);
        self.cursorActive = true;
    } else if (!wantsCursor and self.cursorActive) {
        rl.setMouseCursor(.default);
        self.cursorActive = false;
    }

    if (!self.enabled) {
        self.state = .Disabled;
    } else {
        if (hover) {
            if (rl.isMouseButtonPressed(.left)) {
                self.state = .Active;
                if (self.callbacks.onClick) |handler| handler.call();
            } else {
                self.state = .Hover;
            }
        } else {
            self.state = .Normal;
        }
    }

    if (!rectEquals(self.lastRect, rect) or self.layoutDirty) {
        self.updateLayout();
    }
}

pub fn draw(self: *SpriteButton) !void {
    if (!self.active) return;
    const tint = switch (self.state) {
        .Normal => self.style.tint,
        .Hover => self.style.hoverTint,
        .Active => self.style.activeTint,
        .Disabled => self.style.disabledTint,
    };

    // rl.drawTextureEx(
    //     self.texture,
    //     .{ .x = self.transform.x, .y = self.transform.y },
    //     self.transform.rotation,
    //     self.transform.scale,
    //     tint,
    // );
    //
    rl.drawTexturePro(
        self.texture,
        self.sourceRect,
        self.transform.asRaylibRectangle(),
        .{ .x = 0, .y = 0 },
        self.transform.rotation,
        tint,
    );

    const textColor = switch (self.state) {
        .Normal => self.style.textColor,
        .Hover => self.style.hoverTextColor,
        .Active => self.style.activeTextColor,
        .Disabled => self.style.disabledTextColor,
    };

    const textToDraw: [:0]const u8 = @ptrCast(std.mem.sliceTo(&self.textBuffer, 0));

    rl.drawTextEx(
        self.font,
        textToDraw,
        self.textPosition,
        self.style.fontSize,
        self.style.spacing,
        textColor,
    );
}

pub fn onEvent(self: *SpriteButton, event: UIEvent) void {
    _ = self;
    _ = event;
}

pub fn deinit(self: *SpriteButton) void {
    if (self.cursorActive) {
        rl.setMouseCursor(.default);
    }
}

pub fn setText(self: *SpriteButton, newText: []const u8) void {
    const capped = if (newText.len >= MAX_TEXT_LENGTH) MAX_TEXT_LENGTH - 1 else newText.len;
    self.textBuffer = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8);
    @memcpy(self.textBuffer[0..capped], newText[0..capped]);
    self.textBuffer[capped] = 0;
    self.layoutDirty = true;
}

pub fn setEnabled(self: *SpriteButton, enabled: bool) void {
    self.enabled = enabled;
    self.state = if (enabled) .Normal else .Disabled;
    self.layoutDirty = true;
}

pub fn setStyle(self: *SpriteButton, style: Style) void {
    self.style = style;
    self.font = ResourceManager.getFont(style.font);
    self.layoutDirty = true;
}

fn updateLayout(self: *SpriteButton) void {
    // self.transform.w = @as(f32, @floatFromInt(self.texture.width));
    // self.transform.h = @as(f32, @floatFromInt(self.texture.height));

    const rect = self.transform.asRaylibRectangle();
    self.lastRect = rect;

    const textToMeasure: [:0]const u8 = @ptrCast(std.mem.sliceTo(&self.textBuffer, 0));
    self.textSize = rl.measureTextEx(
        self.font,
        textToMeasure,
        self.style.fontSize,
        self.style.spacing,
    );

    self.textPosition = .{
        .x = rect.x + ((rect.width - self.textSize.x) / 2) + self.style.textOffset.x,
        .y = rect.y + ((rect.height - self.textSize.y) / 2) + self.style.textOffset.y,
    };

    self.layoutDirty = false;
}

fn rectEquals(a: rl.Rectangle, b: rl.Rectangle) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}
