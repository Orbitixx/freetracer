const std = @import("std");
const rl = @import("raylib");

extern fn rl_drag_is_hovering() bool;

const Debug = @import("freetracer-lib").Debug;

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;

const Styles = @import("../Styles.zig");
const Color = Styles.Color;
const TextStyle = Styles.TextStyle;

const ResourceImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceImport.ResourceManagerSingleton;
const TextureResource = ResourceImport.TextureResource;

const FileDropzone = @This();

const MAX_TEXT_LENGTH = 256;
const DEFAULT_TEXT = "Drag & Drop File Here";

const filedDropzoneActiveStyle = Style{
    .backgroundColor = Styles.Color.themeSectionBg,
    .hoverBackgroundColor = rl.Color.init(35, 39, 55, 255),
    .borderColor = Styles.Color.themeOutline,
    .hoverBorderColor = rl.Color.init(90, 110, 120, 255),
    .dashLength = 10,
    .gapLength = 6,
    .borderThickness = 2,
    .iconScale = 0.3,
};

// const fileDropzoneInactiveStyle = Style{
//     .backgroundColor = rl.Color{ .r = 32, .g = 36, .b = 48, .a = 130 },
//     .hoverBackgroundColor = rl.Color{ .r = 45, .g = 50, .b = 64, .a = 170 },
//     .borderColor = Styles.Color.themeOutline,
//     .hoverBorderColor = Styles.Color.lightGray,
//     .dashLength = 12,
//     .gapLength = 6,
//     .borderThickness = 2,
//     .iconScale = 0.3,
// };

pub const ClickHandler = struct {
    function: *const fn (ctx: *anyopaque) void,
    context: *anyopaque,

    pub fn call(self: ClickHandler) void {
        self.function(self.context);
    }
};

pub const DropHandler = struct {
    function: *const fn (ctx: *anyopaque, path: []const u8) void,
    context: *anyopaque,

    pub fn call(self: DropHandler, path: []const u8) void {
        self.function(self.context, path);
    }
};

pub const Callbacks = struct {
    onClick: ?ClickHandler = null,
    onDrop: ?DropHandler = null,
};

pub const Style = struct {
    backgroundColor: rl.Color = Color.transparentDark,
    hoverBackgroundColor: rl.Color = Color.themeSectionBg,
    borderColor: rl.Color = Color.lightGray,
    hoverBorderColor: rl.Color = Color.white,
    borderThickness: f32 = 2,
    dashLength: f32 = 8,
    gapLength: f32 = 4,
    iconScale: f32 = 0.3,
    iconTint: rl.Color = Color.white,
    iconHoverTint: rl.Color = Color.white,
    padding: f32 = 16,
    textOffset: rl.Vector2 = .{ .x = 0, .y = 0 },
    textStyle: TextStyle = .{
        .textColor = Color.lightGray,
        .font = .JERSEY10_REGULAR,
        .fontSize = 24,
        .spacing = 0,
    },
    textHoverColor: ?rl.Color = null,
};

pub const Config = struct {
    identifier: ?UIElementIdentifier = null,
    text: []const u8 = DEFAULT_TEXT,
    style: Style = .{},
    icon: ?TextureResource = null,
    callbacks: Callbacks = .{},
};

const Icon = struct {
    texture: rl.Texture2D,
    scale: f32,
    tint: rl.Color,
    hoverTint: rl.Color,
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    size: rl.Vector2 = .{ .x = 0, .y = 0 },
};

identifier: ?UIElementIdentifier = null,
transform: Transform = .{},
style: Style = .{},
callbacks: Callbacks = .{},

font: rl.Font,
textBuffer: [MAX_TEXT_LENGTH:0]u8 = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8),
textSize: rl.Vector2 = .{ .x = 0, .y = 0 },
textPosition: rl.Vector2 = .{ .x = 0, .y = 0 },

icon: ?Icon = null,

hover: bool = false,
drag: bool = false,
cursorActive: bool = false,
layoutDirty: bool = true,
lastRect: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

pub fn init(config: Config) FileDropzone {
    var dropzone = FileDropzone{
        .identifier = config.identifier,
        .style = filedDropzoneActiveStyle,
        .callbacks = config.callbacks,
        .font = ResourceManager.getFont(config.style.textStyle.font),
    };

    if (config.icon) |resource| {
        dropzone.icon = .{
            .texture = ResourceManager.getTexture(resource),
            .scale = config.style.iconScale,
            .tint = config.style.iconTint,
            .hoverTint = config.style.iconHoverTint,
        };
        dropzone.updateIconSize();
    }

    dropzone.setText(config.text);
    return dropzone;
}

pub fn start(self: *FileDropzone) !void {
    Debug.log(.DEBUG, "FileDropzone start()", .{});
    self.transform.resolve();

    self.updateLayout();
}

pub fn update(self: *FileDropzone) !void {
    self.transform.resolve();
    const rect = self.transform.asRaylibRectangle();

    const mouse = rl.getMousePosition();
    self.hover = rl.checkCollisionPointRec(mouse, rect);
    self.drag = rl_drag_is_hovering();

    const wantsCursor = self.hover or self.drag;
    if (wantsCursor and !self.cursorActive) {
        rl.setMouseCursor(.pointing_hand);
        self.cursorActive = true;
    } else if (!wantsCursor and self.cursorActive) {
        rl.setMouseCursor(.default);
        self.cursorActive = false;
    }

    if (self.hover and rl.isMouseButtonPressed(.left)) {
        if (self.callbacks.onClick) |handler| {
            handler.call();
        }
    }

    if (rl.isFileDropped()) {
        const dropped = rl.loadDroppedFiles();
        defer rl.unloadDroppedFiles(dropped);

        if (dropped.count > 0 and self.hover) {
            if (self.callbacks.onDrop) |handler| {
                const pathSlice = std.mem.span(dropped.paths[0]);
                if (pathSlice.len > 0) {
                    handler.call(pathSlice);
                }
            }
        }
    }

    if (!rectEquals(self.lastRect, rect) or self.layoutDirty) {
        self.updateLayout();
    }
}

pub fn draw(self: *FileDropzone) !void {
    const rect = self.transform.asRaylibRectangle();
    const highlight = self.hover or self.drag;

    const bgColor = if (highlight) filedDropzoneActiveStyle.hoverBackgroundColor else filedDropzoneActiveStyle.backgroundColor;
    rl.drawRectangleRec(rect, bgColor);

    const borderColor = if (highlight) filedDropzoneActiveStyle.hoverBorderColor else filedDropzoneActiveStyle.borderColor;
    drawDashedBorder(
        rect,
        borderColor,
        self.style.borderThickness,
        self.style.dashLength,
        self.style.gapLength,
    );

    if (self.icon) |icon| {
        const tint = if (highlight) icon.hoverTint else icon.tint;
        rl.drawTextureEx(
            icon.texture,
            icon.position,
            0,
            icon.scale,
            tint,
        );
    }

    if (highlight) {
        const textColor = if (self.style.textHoverColor) |hoverColor| hoverColor else self.style.textStyle.textColor;
        const textToDraw: [:0]const u8 = @ptrCast(std.mem.sliceTo(&self.textBuffer, 0));

        rl.drawTextEx(
            self.font,
            textToDraw,
            self.textPosition,
            self.style.textStyle.fontSize,
            self.style.textStyle.spacing,
            textColor,
        );
    }
}

pub fn onEvent(self: *FileDropzone, event: UIEvent) void {
    _ = self;
    _ = event;
}

pub fn deinit(self: *FileDropzone) void {
    if (self.cursorActive) {
        rl.setMouseCursor(.default);
    }
    if (self.icon) |icon| {
        _ = icon;
    }
}

pub fn setText(self: *FileDropzone, newText: []const u8) void {
    self.textBuffer = std.mem.zeroes([MAX_TEXT_LENGTH:0]u8);

    const cappedLen: usize = if (newText.len >= MAX_TEXT_LENGTH) MAX_TEXT_LENGTH - 1 else newText.len;
    @memcpy(self.textBuffer[0..cappedLen], newText[0..cappedLen]);
    self.textBuffer[cappedLen] = 0;
    self.layoutDirty = true;
}

pub fn setStyle(self: *FileDropzone, style: Style) void {
    self.style = style;
    self.font = ResourceManager.getFont(style.textStyle.font);

    if (self.icon) |*icon| {
        icon.scale = style.iconScale;
        icon.tint = style.iconTint;
        icon.hoverTint = style.iconHoverTint;
        self.updateIconSize();
    }

    self.layoutDirty = true;
}

pub fn setIcon(self: *FileDropzone, resource: ?TextureResource) void {
    if (resource) |res| {
        self.icon = .{
            .texture = ResourceManager.getTexture(res),
            .scale = self.style.iconScale,
            .tint = self.style.iconTint,
            .hoverTint = self.style.iconHoverTint,
        };
        self.updateIconSize();
    } else {
        self.icon = null;
    }
    self.layoutDirty = true;
}

fn updateLayout(self: *FileDropzone) void {
    self.transform.resolve();
    const rect = self.transform.asRaylibRectangle();
    self.lastRect = rect;

    const paddedRect = rl.Rectangle{
        .x = rect.x + self.style.padding,
        .y = rect.y + self.style.padding,
        .width = @max(0.0, rect.width - (self.style.padding * 2)),
        .height = @max(0.0, rect.height - (self.style.padding * 2)),
    };

    const textToMeasure: [:0]const u8 = @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00));

    self.textSize = rl.measureTextEx(
        self.font,
        textToMeasure,
        self.style.textStyle.fontSize,
        self.style.textStyle.spacing,
    );

    const centerX = paddedRect.x + (paddedRect.width / 2);
    const centerY = paddedRect.y + (paddedRect.height / 2);

    if (self.icon) |*icon| {
        self.updateIconSize();
        icon.position = .{
            .x = centerX - (icon.size.x / 2),
            .y = centerY - (icon.size.y / 2),
        };
    }

    self.textPosition = .{
        .x = centerX - (self.textSize.x / 2) + self.style.textOffset.x,
        .y = centerY - (self.textSize.y / 2) + self.style.textOffset.y,
    };

    self.layoutDirty = false;
}

fn updateIconSize(self: *FileDropzone) void {
    if (self.icon) |*icon| {
        icon.scale = self.style.iconScale;
        icon.size = .{
            .x = @as(f32, @floatFromInt(icon.texture.width)) * icon.scale,
            .y = @as(f32, @floatFromInt(icon.texture.height)) * icon.scale,
        };
    }
}

fn drawDashedBorder(
    rect: rl.Rectangle,
    color: rl.Color,
    thickness: f32,
    dashLength: f32,
    gapLength: f32,
) void {
    const dash = @max(dashLength, 1.0);
    const gap = @max(gapLength, 0.0);
    const perimeter = 2 * (rect.width + rect.height);

    var progress: f32 = 0;
    while (progress < perimeter) : (progress += dash + gap) {
        const endProgress = @min(progress + dash, perimeter);
        const startPoint = pointAlongRect(rect, progress);
        const endPoint = pointAlongRect(rect, endProgress);
        rl.drawLineEx(startPoint, endPoint, thickness, color);
    }
}

fn pointAlongRect(rect: rl.Rectangle, distance: f32) rl.Vector2 {
    var remaining = distance;
    const edges = [_]struct { start: rl.Vector2, delta: rl.Vector2, length: f32 }{
        .{ .start = .{ .x = rect.x, .y = rect.y }, .delta = .{ .x = rect.width, .y = 0 }, .length = rect.width },
        .{ .start = .{ .x = rect.x + rect.width, .y = rect.y }, .delta = .{ .x = 0, .y = rect.height }, .length = rect.height },
        .{ .start = .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, .delta = .{ .x = -rect.width, .y = 0 }, .length = rect.width },
        .{ .start = .{ .x = rect.x, .y = rect.y + rect.height }, .delta = .{ .x = 0, .y = -rect.height }, .length = rect.height },
    };

    for (edges) |edge| {
        if (remaining <= edge.length) {
            return .{
                .x = edge.start.x + edge.delta.x * (remaining / edge.length),
                .y = edge.start.y + edge.delta.y * (remaining / edge.length),
            };
        }
        remaining -= edge.length;
    }

    return .{ .x = rect.x, .y = rect.y };
}

fn rectEquals(a: rl.Rectangle, b: rl.Rectangle) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}
