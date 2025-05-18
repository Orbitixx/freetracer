const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const rl = @import("raylib");
const ResourceManagerImport = @import("../../managers/ResourceManager.zig");
const ResourceManager = ResourceManagerImport.ResourceManagerSingleton;

const Font = ResourceManagerImport.FONT;

pub const Point = struct {
    x: f32,
    y: f32,
};

pub const Rectangle = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    rounded: bool = false,
    color: rl.Color = .gray,

    pub fn draw(self: Rectangle) void {
        if (self.rounded) {
            rl.drawRectangleRounded(self.asRaylibRectangle(), 0.2, 6, self.color);
            return;
        }

        rl.drawRectanglePro(self.asRaylibRectangle(), .{ .x = 0, .y = 0 }, 0, self.color);
    }

    pub fn isPointWithinBounds(self: Rectangle, p: Point) bool {
        if ((p.x >= self.x and p.x <= 2 * self.x + self.w) and
            (p.y >= self.y and p.y <= 2 * self.y + self.w)) return true else return false;
    }

    pub fn asRaylibRectangle(self: Rectangle) rl.Rectangle {
        return .{
            .x = self.x,
            .y = self.y,
            .width = self.w,
            .height = self.h,
        };
    }

    /// Returns absolute X coordinate relative to the Rectange's position and width
    pub fn relW(self: Rectangle, x: f32) f32 {
        return self.x + self.w * x;
    }

    /// Returns absolute X coordinate relative to the Rectange's position and width
    pub fn relH(self: Rectangle, y: f32) f32 {
        return self.y + self.h * y;
    }
};

pub const Text = struct {
    bounds: Rectangle = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    value: [:0]const u8,
    font: rl.Font,
    fontSize: f32,
    color: rl.Color = .white,

    pub fn init(value: [:0]const u8, position: rl.Vector2, font: Font, fontSize: f32, color: rl.Color) Text {
        const _font: rl.Font = ResourceManager.getFont(font);
        const textDims: rl.Vector2 = rl.measureTextEx(_font, value, fontSize, 0);

        return .{
            .bounds = .{
                .x = position.x,
                .y = position.y,
                .w = textDims.x,
                .h = textDims.y,
            },
            .value = value,
            .font = _font,
            .fontSize = fontSize,
            .color = color,
        };
    }

    pub fn draw(self: Text) void {
        rl.drawTextEx(
            self.font,
            self.value,
            self.getPosition(),
            self.fontSize,
            0,
            self.color,
        );
    }

    pub fn getPosition(self: Text) rl.Vector2 {
        return .{ .x = self.bounds.x, .y = self.bounds.y };
    }
};
