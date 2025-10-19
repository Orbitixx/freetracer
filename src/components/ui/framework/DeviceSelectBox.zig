const std = @import("std");
const rl = @import("raylib");
const meta = std.meta;

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElementCallbacks = UIFramework.UIElementCallbacks;

const Styles = @import("../Styles.zig");
const TextStyle = Styles.TextStyle;
const Color = Styles.Color;

const ResourceManagerImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceManagerImport.ResourceManagerSingleton;
const TextureResource = ResourceManagerImport.TextureResource;
const FontResource = ResourceManagerImport.FONT;

const DeviceSelectBox = @This();

const MAX_TEXT_LENGTH = 192;

pub const DeviceKind = enum {
    usb,
    sd,
    other,
};

pub const Content = struct {
    name: [:0]const u8,
    path: [:0]const u8,
    media: [:0]const u8,
};

pub const Style = struct {
    backgroundColor: rl.Color = Color.themeSectionBg,
    hoverBackgroundColor: rl.Color = rl.Color.init(40, 43, 57, 255),
    selectedBackgroundColor: rl.Color = rl.Color.init(42, 73, 87, 255),
    disabledBackgroundColor: rl.Color = Color.transparentDark,
    iconTint: rl.Color = Color.white,
    borderColor: rl.Color = Color.themePrimary,
    borderThickness: f32 = 3,
    cornerRadius: f32 = 0.12,
    cornerSegments: i32 = 8,
    padding: f32 = 18,
    iconFraction: f32 = 0.24,
    contentSpacing: f32 = 18,
    lineSpacing: f32 = 4,
    primaryText: TextStyle = .{ .font = FontResource.ROBOTO_REGULAR, .fontSize = 22, .textColor = Color.white },
    secondaryText: TextStyle = .{ .font = FontResource.ROBOTO_REGULAR, .fontSize = 16, .textColor = Color.offWhite },
    detailText: TextStyle = .{ .font = FontResource.ROBOTO_REGULAR, .fontSize = 14, .textColor = Color.lightGray },
    scale: f32 = 1,
};

pub const Config = struct {
    identifier: ?UIElementIdentifier = null,
    deviceKind: DeviceKind = .other,
    content: Content,
    style: Style = .{},
    callbacks: UIElementCallbacks = .{},
    selected: bool = false,
    enabled: bool = true,
    serviceId: ?usize = null,
};

identifier: ?UIElementIdentifier = null,
transform: Transform = .{},
style: Style = .{},
callbacks: UIElementCallbacks = .{},

active: bool = true,
enabled: bool = true,
selected: bool = false,
hovered: bool = false,
cursorActive: bool = false,
deviceKind: DeviceKind = .other,
serviceId: ?usize = null,

iconInactive: rl.Texture2D,
iconActive: rl.Texture2D,

primaryFont: rl.Font,
secondaryFont: rl.Font,
detailFont: rl.Font,

nameBuffer: [MAX_TEXT_LENGTH:0]u8 = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8),
pathBuffer: [MAX_TEXT_LENGTH:0]u8 = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8),
mediaBuffer: [MAX_TEXT_LENGTH:0]u8 = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8),

lastRect: rl.Rectangle = rectZero(),
iconRect: rl.Rectangle = rectZero(),
primaryPos: rl.Vector2 = .{ .x = 0, .y = 0 },
secondaryPos: rl.Vector2 = .{ .x = 0, .y = 0 },
detailPos: rl.Vector2 = .{ .x = 0, .y = 0 },
layoutDirty: bool = true,

pub fn init(config: Config) DeviceSelectBox {
    var box = DeviceSelectBox{
        .identifier = config.identifier,
        .style = config.style,
        .callbacks = config.callbacks,
        .active = true,
        .enabled = config.enabled,
        .selected = config.selected,
        .deviceKind = config.deviceKind,
        .serviceId = config.serviceId,
        .iconInactive = resolveIconTexture(config.deviceKind, false),
        .iconActive = resolveIconTexture(config.deviceKind, true),
        .primaryFont = ResourceManager.getFont(config.style.primaryText.font),
        .secondaryFont = ResourceManager.getFont(config.style.secondaryText.font),
        .detailFont = ResourceManager.getFont(config.style.detailText.font),
    };

    box.storeText(&box.nameBuffer, config.content.name);
    box.storeText(&box.pathBuffer, config.content.path);
    box.storeText(&box.mediaBuffer, config.content.media);

    return box;
}

pub fn start(self: *DeviceSelectBox) !void {
    self.transform.resolve();
    self.lastRect = self.transform.asRaylibRectangle();
    self.updateLayout(self.lastRect);
}

pub fn update(self: *DeviceSelectBox) !void {
    if (!self.active) return;

    self.transform.resolve();
    const rect = self.transform.asRaylibRectangle();

    if (!rectEquals(self.lastRect, rect) or self.layoutDirty) {
        self.updateLayout(rect);
    }

    const mouse = rl.getMousePosition();
    const hover = self.enabled and rl.checkCollisionPointRec(mouse, rect);

    if (hover != self.cursorActive) {
        rl.setMouseCursor(if (hover) .pointing_hand else .default);
        self.cursorActive = hover;
    }

    self.hovered = hover;

    if (hover and self.enabled and rl.isMouseButtonReleased(.left)) {
        if (self.callbacks.onClick) |handler| handler.call();
    }
}

pub fn draw(self: *DeviceSelectBox) !void {
    if (!self.active) return;

    const rect = self.lastRect;
    const background = if (!self.enabled)
        self.style.disabledBackgroundColor
    else if (self.selected)
        self.style.selectedBackgroundColor
    else if (self.hovered)
        self.style.hoverBackgroundColor
    else
        self.style.backgroundColor;

    rl.drawRectangleRounded(rect, self.style.cornerRadius, self.style.cornerSegments, background);

    if (self.selected) {
        rl.drawRectangleRoundedLinesEx(
            rect,
            self.style.cornerRadius,
            self.style.cornerSegments,
            self.style.borderThickness,
            self.style.borderColor,
        );
    }

    const tex = if (self.selected) self.iconActive else self.iconInactive;
    const source = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(tex.width)),
        .height = @as(f32, @floatFromInt(tex.height)),
    };

    rl.drawTexturePro(
        tex,
        source,
        self.iconRect,
        .{ .x = 0, .y = 0 },
        0,
        self.style.iconTint,
    );

    rl.drawTextEx(
        self.primaryFont,
        @ptrCast(std.mem.sliceTo(&self.nameBuffer, 0x00)),
        self.primaryPos,
        self.style.primaryText.fontSize,
        self.style.primaryText.spacing,
        self.style.primaryText.textColor,
    );

    rl.drawTextEx(
        self.secondaryFont,
        @ptrCast(std.mem.sliceTo(&self.pathBuffer, 0x00)),
        self.secondaryPos,
        self.style.secondaryText.fontSize,
        self.style.secondaryText.spacing,
        self.style.secondaryText.textColor,
    );

    rl.drawTextEx(
        self.detailFont,
        @ptrCast(std.mem.sliceTo(&self.mediaBuffer, 0x00)),
        self.detailPos,
        self.style.detailText.fontSize,
        self.style.detailText.spacing,
        self.style.detailText.textColor,
    );
}

pub fn onEvent(self: *DeviceSelectBox, event: UIEvent) void {
    switch (event) {
        .StateChanged => |e| {
            if (e.target) |target| {
                if (target != self.identifier) return;
                self.setSelected(e.isActive);
            } else {
                self.setActive(e.isActive);
            }
        },
        else => {},
    }
}

pub fn setSelected(self: *DeviceSelectBox, flag: bool) void {
    if (self.selected == flag) return;
    self.selected = flag;
    self.layoutDirty = true;
    if (self.callbacks.onStateChange) |handler| handler.call(flag);
}

pub fn setActive(self: *DeviceSelectBox, flag: bool) void {
    if (self.active == flag) return;
    self.active = flag;
    if (!flag and self.cursorActive) {
        rl.setMouseCursor(.default);
        self.cursorActive = false;
        self.hovered = false;
    }
}

pub fn setEnabled(self: *DeviceSelectBox, flag: bool) void {
    self.enabled = flag;
}

pub fn setContent(self: *DeviceSelectBox, content: Content) void {
    self.storeText(&self.nameBuffer, content.name);
    self.storeText(&self.pathBuffer, content.path);
    self.storeText(&self.mediaBuffer, content.media);
    self.layoutDirty = true;
}

pub fn setDeviceKind(self: *DeviceSelectBox, kind: DeviceKind) void {
    if (self.deviceKind == kind) return;
    self.deviceKind = kind;
    self.iconInactive = resolveIconTexture(kind, false);
    self.iconActive = resolveIconTexture(kind, true);
    self.layoutDirty = true;
}

pub fn serviceIdentifier(self: *const DeviceSelectBox) ?usize {
    return self.serviceId;
}

pub fn deinit(self: *DeviceSelectBox) void {
    _ = self;
}

fn storeText(_: *DeviceSelectBox, buffer: *[MAX_TEXT_LENGTH:0]u8, value: [:0]const u8) void {
    buffer.* = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8);
    const len = @min(value.len, MAX_TEXT_LENGTH - 1);
    if (len > 0) @memcpy(buffer[0..len], value[0..len]);
    buffer[len] = 0;
}

fn updateLayout(self: *DeviceSelectBox, rect: rl.Rectangle) void {
    self.lastRect = rect;
    self.layoutDirty = false;

    const padded = rl.Rectangle{
        .x = rect.x + self.style.padding,
        .y = rect.y + self.style.padding,
        .width = @max(0.0, rect.width - self.style.padding * 2),
        .height = @max(0.0, rect.height - self.style.padding * 2),
    };

    const iconAreaWidth = padded.width * self.style.iconFraction;
    const iconAreaHeight = padded.height;
    const tex = if (self.selected) self.iconActive else self.iconInactive;
    const texWidth: f32 = @floatFromInt(tex.width);
    const texHeight: f32 = @floatFromInt(tex.height);
    const aspect = if (texHeight == 0) 1 else texWidth / texHeight;

    var targetWidth = iconAreaWidth;
    var targetHeight = if (aspect == 0) iconAreaHeight else targetWidth / aspect;

    if (targetHeight > iconAreaHeight) {
        targetHeight = iconAreaHeight;
        targetWidth = targetHeight * aspect;
    }

    self.iconRect = rl.Rectangle{
        .x = padded.x + (iconAreaWidth - targetWidth) / 2,
        .y = rect.y + (rect.height - targetHeight) / 2,
        .width = targetWidth * self.style.scale,
        .height = targetHeight * self.style.scale,
    };

    const contentStartX = padded.x + iconAreaWidth + self.style.contentSpacing;

    const nameDims = rl.measureTextEx(self.primaryFont, @ptrCast(std.mem.sliceTo(&self.nameBuffer, 0x00)), self.style.primaryText.fontSize, self.style.primaryText.spacing);
    const pathDims = rl.measureTextEx(self.secondaryFont, @ptrCast(std.mem.sliceTo(&self.pathBuffer, 0x00)), self.style.secondaryText.fontSize, self.style.secondaryText.spacing);
    const mediaDims = rl.measureTextEx(self.detailFont, @ptrCast(std.mem.sliceTo(&self.mediaBuffer, 0x00)), self.style.detailText.fontSize, self.style.detailText.spacing);

    const totalTextHeight = nameDims.y + pathDims.y + mediaDims.y + self.style.lineSpacing * 2;
    const baseY = rect.y + (rect.height - totalTextHeight) / 2;

    self.primaryPos = .{ .x = contentStartX, .y = baseY };
    self.secondaryPos = .{ .x = contentStartX, .y = baseY + nameDims.y + self.style.lineSpacing };
    self.detailPos = .{ .x = contentStartX, .y = self.secondaryPos.y + pathDims.y + self.style.lineSpacing };
}

fn resolveIconTexture(kind: DeviceKind, selected: bool) rl.Texture2D {
    const resource: TextureResource = switch (kind) {
        .usb => if (selected) .USB_ICON_ACTIVE else .USB_ICON_INACTIVE,
        .sd => if (selected) .SD_ICON_ACTIVE else .SD_ICON_INACTIVE,
        .other => if (selected) .USB_ICON_ACTIVE else .USB_ICON_INACTIVE,
    };
    return ResourceManager.getTexture(resource);
}

fn rectZero() rl.Rectangle {
    return rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
}

fn rectEquals(a: rl.Rectangle, b: rl.Rectangle) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}
