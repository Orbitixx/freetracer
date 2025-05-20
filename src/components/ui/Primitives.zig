const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const rl = @import("raylib");
const ResourceManagerImport = @import("../../managers/ResourceManager.zig");
const ResourceManager = ResourceManagerImport.ResourceManagerSingleton;

const Styles = @import("./Styles.zig");
const TextStyle = Styles.TextStyle;
const RectangleStyle = Styles.RectangleStyle;

const AppFont = ResourceManagerImport.FONT;

pub const Transform = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    scale: f32 = 1.0,
    rotation: f32 = 0.0,

    pub fn getPosition(self: Transform) rl.Vector2 {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn isPointWithinBounds(self: Transform, p: rl.Vector2) bool {
        if ((p.x >= self.x and p.x <= self.x + self.w) and
            (p.y >= self.y and p.y <= self.y + self.h)) return true else return false;
    }

    /// Returns absolute X coordinate relative to the Rectange's position and width
    pub fn relX(self: Transform, x: f32) f32 {
        return self.x + self.w * x;
    }

    /// Returns absolute X coordinate relative to the Rectange's position and width
    pub fn relY(self: Transform, y: f32) f32 {
        return self.y + self.h * y;
    }

    pub fn asRaylibRectangle(self: Transform) rl.Rectangle {
        return .{
            .x = self.x,
            .y = self.y,
            .width = self.w,
            .height = self.h,
        };
    }
};

pub const Rectangle = struct {
    transform: Transform,
    rounded: bool = false,
    style: RectangleStyle = .{},

    pub fn draw(self: Rectangle) void {
        if (self.rounded) {
            rl.drawRectangleRounded(self.transform.asRaylibRectangle(), 0.2, 6, self.style.color);
            return;
        }

        rl.drawRectanglePro(self.transform.asRaylibRectangle(), .{ .x = 0, .y = 0 }, 0, self.style.color);
    }
};

pub const TextDimensions = struct {
    width: f32,
    height: f32,
};

pub const Text = struct {
    transform: Transform = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    value: [:0]const u8,
    style: TextStyle,
    font: rl.Font,

    /// Static init() function; returns a new instance of Text
    pub fn init(value: [:0]const u8, position: rl.Vector2, style: TextStyle) Text {
        const _font: rl.Font = ResourceManager.getFont(style.font);

        const textDims: rl.Vector2 = rl.measureTextEx(_font, value, style.fontSize, style.spacing);

        return .{
            .transform = .{
                .x = position.x,
                .y = position.y,
                .w = textDims.x,
                .h = textDims.y,
            },
            .value = value,
            .style = style,
            .font = _font,
        };
    }

    pub fn draw(self: Text) void {
        rl.drawTextEx(
            self.font,
            self.value,
            self.transform.getPosition(),
            self.style.fontSize,
            self.style.spacing,
            self.style.textColor,
        );
    }

    pub fn getDimensions(self: Text) TextDimensions {
        const dims = rl.measureTextEx(self.font, self.value, self.style.fontSize, self.style.spacing);
        return .{ .width = dims.x, .height = dims.y };
    }
};
