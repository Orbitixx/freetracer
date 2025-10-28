const std = @import("std");
const rl = @import("raylib");

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const SizeSpec = UIFramework.SizeSpec;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElementCallbacks = UIFramework.UIElementCallbacks;

const Styles = @import("../Styles.zig");
const TextStyle = Styles.TextStyle;
const Color = Styles.Color;

const ResourceImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceImport.ResourceManagerSingleton;
const TextureResource = ResourceImport.TextureResource;
const FontResource = ResourceImport.FONT;

const TexturedCheckbox = @This();

const MAX_TEXT_LENGTH = 192;

pub const State = enum {
    Normal,
    Hover,
    Checked,
    Disabled,
};

pub const StateStyle = struct {
    tint: rl.Color = Color.offWhite,
    text: TextStyle = .{
        .font = FontResource.ROBOTO_REGULAR,
        .fontSize = 16,
        .spacing = 0,
        .textColor = Color.white,
    },
};

pub const Style = struct {
    normal: StateStyle = .{},
    hover: StateStyle = .{
        .tint = Color.themeSecondary,
        .text = .{
            .font = FontResource.ROBOTO_REGULAR,
            .fontSize = 16,
            .spacing = 0,
            .textColor = Color.themeSecondary,
        },
    },
    checked: StateStyle = .{
        .tint = Color.white,
        .text = .{
            .font = FontResource.ROBOTO_REGULAR,
            .fontSize = 16,
            .spacing = 0,
            .textColor = Color.white,
        },
    },
    disabled: StateStyle = .{
        .tint = Color.lightGray,
        .text = .{
            .font = FontResource.ROBOTO_REGULAR,
            .fontSize = 16,
            .spacing = 0,
            .textColor = Color.lightGray,
        },
    },
    spacing: f32 = 10,
    textureScale: f32 = 1,
};

pub const Config = struct {
    identifier: ?UIElementIdentifier = null,
    text: []const u8,
    style: Style = .{},
    callbacks: UIElementCallbacks = .{},
    checked: bool = false,
    enabled: bool = true,
};

identifier: ?UIElementIdentifier = null,
transform: Transform = .{},
style: Style = .{},
callbacks: UIElementCallbacks = .{},

active: bool = true,
enabled: bool = true,
checked: bool = false,
hovered: bool = false,
cursorActive: bool = false,
autoSize: bool = true,

normalTexture: rl.Texture2D,
checkedTexture: rl.Texture2D,
sourceRectNormal: rl.Rectangle,
sourceRectChecked: rl.Rectangle,
checkboxRect: rl.Rectangle = rectZero(),
interactiveRect: rl.Rectangle = rectZero(),

font: rl.Font,

textBuffer: [MAX_TEXT_LENGTH:0]u8 = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8),
textSize: rl.Vector2 = .{ .x = 0, .y = 0 },
textPosition: rl.Vector2 = .{ .x = 0, .y = 0 },

layoutDirty: bool = true,
lastRect: rl.Rectangle = rectZero(),
lastLayoutState: State = .Normal,

pub fn init(config: Config) TexturedCheckbox {
    var buffer = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8);
    const capped = if (config.text.len >= MAX_TEXT_LENGTH) MAX_TEXT_LENGTH - 1 else config.text.len;
    @memcpy(buffer[0..capped], config.text[0..capped]);
    buffer[capped] = 0;

    const normalTexture = ResourceManager.getTexture(TextureResource.CHECKBOX_NORMAL);
    const checkedTexture = ResourceManager.getTexture(TextureResource.CHECKBOX_CHECKED);

    const font = ResourceManager.getFont(config.style.normal.text.font);

    const textMeasure = rl.measureTextEx(
        font,
        @ptrCast(std.mem.sliceTo(&buffer, 0)),
        config.style.normal.text.fontSize,
        config.style.normal.text.spacing,
    );

    const checkboxWidth = @as(f32, @floatFromInt(normalTexture.width)) * config.style.textureScale;
    const checkboxHeight = @as(f32, @floatFromInt(normalTexture.height)) * config.style.textureScale;
    const desiredHeight = @max(checkboxHeight, textMeasure.y);
    const desiredWidth = checkboxWidth + config.style.spacing + textMeasure.x;
    const initial_state: State = if (!config.enabled)
        .Disabled
    else if (config.checked)
        .Checked
    else
        .Normal;

    return .{
        .identifier = config.identifier,
        .style = config.style,
        .callbacks = config.callbacks,
        .enabled = config.enabled,
        .checked = config.checked,
        .normalTexture = normalTexture,
        .checkedTexture = checkedTexture,
        .sourceRectNormal = textureSource(normalTexture),
        .sourceRectChecked = textureSource(checkedTexture),
        .font = font,
        .textBuffer = buffer,
        .transform = .{
            .size = SizeSpec.pixels(desiredWidth, desiredHeight),
        },
        .autoSize = true,
        .lastLayoutState = initial_state,
    };
}

pub fn start(self: *TexturedCheckbox) !void {
    self.transform.resolve();
    self.layoutDirty = true;
    self.lastLayoutState = self.currentState();
    self.updateLayout(self.transform.asRaylibRectangle(), self.lastLayoutState);
}

pub fn update(self: *TexturedCheckbox) !void {
    if (!self.active) {
        if (self.cursorActive) {
            rl.setMouseCursor(.default);
            self.cursorActive = false;
        }
        self.hovered = false;
        return;
    }

    self.transform.resolve();
    const rect = self.transform.asRaylibRectangle();
    const layoutState = self.currentState();

    if (!rectEquals(rect, self.lastRect) or self.layoutDirty or layoutState != self.lastLayoutState) {
        self.updateLayout(rect, layoutState);
    }

    const mouse = rl.getMousePosition();
    const hover = self.enabled and rl.checkCollisionPointRec(mouse, self.interactiveRect);

    if (hover != self.cursorActive) {
        rl.setMouseCursor(if (hover) .pointing_hand else .default);
        self.cursorActive = hover;
    }

    self.hovered = hover;

    if (hover and self.enabled and rl.isMouseButtonReleased(.left)) {
        self.checked = !self.checked;
        self.layoutDirty = true;
        if (self.callbacks.onClick) |handler| handler.call();
        if (self.callbacks.onStateChange) |handler| handler.call(self.checked);
    }

    const state = self.currentState();
    if (self.layoutDirty or state != self.lastLayoutState) {
        self.updateLayout(self.transform.asRaylibRectangle(), state);
    }
}

pub fn draw(self: *TexturedCheckbox) !void {
    if (!self.active) return;

    const state = self.currentState();
    const styleState = self.styleFor(state);
    const texture = if (self.checked) self.checkedTexture else self.normalTexture;
    const source = if (self.checked) self.sourceRectChecked else self.sourceRectNormal;

    rl.drawTexturePro(
        texture,
        source,
        self.checkboxRect,
        .{ .x = 0, .y = 0 },
        0,
        styleState.tint,
    );

    rl.drawTextEx(
        self.font,
        self.textAsSlice(),
        self.textPosition,
        styleState.text.fontSize,
        styleState.text.spacing,
        styleState.text.textColor,
    );
}

pub fn onEvent(self: *TexturedCheckbox, event: UIEvent) void {
    switch (event) {
        inline else => |ev| if (ev.target != self.identifier) return,
    }

    switch (event) {
        .EnabledChanged => |ev| {
            self.enabled = ev.enabled;
        },
        else => {},
    }
}

pub fn deinit(self: *TexturedCheckbox) void {
    if (self.cursorActive) rl.setMouseCursor(.default);
}

pub fn setChecked(self: *TexturedCheckbox, flag: bool) void {
    if (self.checked == flag) return;
    self.checked = flag;
    self.layoutDirty = true;
    if (self.callbacks.onStateChange) |handler| handler.call(self.checked);
}

pub fn toggle(self: *TexturedCheckbox) void {
    self.setChecked(!self.checked);
}

pub fn isChecked(self: TexturedCheckbox) bool {
    return self.checked;
}

pub fn setEnabled(self: *TexturedCheckbox, flag: bool) void {
    if (self.enabled == flag) return;
    self.enabled = flag;
    if (!flag and self.cursorActive) {
        rl.setMouseCursor(.default);
        self.cursorActive = false;
    }
    if (!flag) self.hovered = false;
    self.layoutDirty = true;
}

pub fn setText(self: *TexturedCheckbox, value: []const u8) void {
    const capped = if (value.len >= MAX_TEXT_LENGTH) MAX_TEXT_LENGTH - 1 else value.len;
    self.textBuffer = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8);
    @memcpy(self.textBuffer[0..capped], value[0..capped]);
    self.textBuffer[capped] = 0;
    self.layoutDirty = true;
}

pub fn setStyle(self: *TexturedCheckbox, style: Style) void {
    self.style = style;
    self.font = ResourceManager.getFont(style.normal.text.font);
    self.layoutDirty = true;
}

pub fn setCallbacks(self: *TexturedCheckbox, callbacks: UIElementCallbacks) void {
    self.callbacks = callbacks;
}

fn updateLayout(self: *TexturedCheckbox, rect: rl.Rectangle, state: State) void {
    const styleState = self.styleFor(state);

    self.textSize = rl.measureTextEx(
        self.font,
        self.textAsSlice(),
        styleState.text.fontSize,
        styleState.text.spacing,
    );

    const baseWidth = @as(f32, @floatFromInt(self.normalTexture.width)) * self.style.textureScale;
    const baseHeight = @as(f32, @floatFromInt(self.normalTexture.height)) * self.style.textureScale;

    var targetRect = rect;
    if (self.autoSize) {
        const desiredWidth = baseWidth + self.style.spacing + self.textSize.x;
        const desiredHeight = @max(baseHeight, self.textSize.y);
        self.transform.size = SizeSpec.pixels(desiredWidth, desiredHeight);
        self.transform.resolve();
        targetRect = self.transform.asRaylibRectangle();
    }

    if (targetRect.width == 0 or targetRect.height == 0) {
        self.transform.resolve();
        targetRect = self.transform.asRaylibRectangle();
    }

    const targetHeight = if (targetRect.height > 0) targetRect.height else baseHeight;
    const scale = if (baseHeight == 0) 1 else targetHeight / baseHeight;
    const checkboxWidth = baseWidth * scale;
    const checkboxHeight = baseHeight * scale;

    self.checkboxRect = .{
        .x = targetRect.x,
        .y = targetRect.y + (targetHeight - checkboxHeight) / 2,
        .width = checkboxWidth,
        .height = checkboxHeight,
    };

    self.textPosition = .{
        .x = self.checkboxRect.x + self.checkboxRect.width + self.style.spacing,
        .y = targetRect.y + (targetHeight - self.textSize.y) / 2,
    };

    const textWidth = self.textSize.x;
    const totalWidth = (self.textPosition.x + textWidth) - targetRect.x;
    self.interactiveRect = .{
        .x = targetRect.x,
        .y = targetRect.y,
        .width = totalWidth,
        .height = targetHeight,
    };

    self.lastRect = targetRect;
    self.lastLayoutState = state;
    self.layoutDirty = false;
}

fn currentState(self: TexturedCheckbox) State {
    if (!self.enabled) return .Disabled;
    if (self.hovered) return .Hover;
    if (self.checked) return .Checked;
    return .Normal;
}

fn styleFor(self: TexturedCheckbox, state: State) StateStyle {
    return switch (state) {
        .Normal => self.style.normal,
        .Hover => self.style.hover,
        .Checked => self.style.checked,
        .Disabled => self.style.disabled,
    };
}

fn textAsSlice(self: *const TexturedCheckbox) [:0]const u8 {
    return @ptrCast(std.mem.sliceTo(&self.textBuffer, 0));
}

fn rectZero() rl.Rectangle {
    return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
}

fn rectEquals(a: rl.Rectangle, b: rl.Rectangle) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}

fn textureSource(texture: rl.Texture2D) rl.Rectangle {
    return .{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(texture.width)),
        .height = @as(f32, @floatFromInt(texture.height)),
    };
}
