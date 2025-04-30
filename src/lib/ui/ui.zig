const std = @import("std");
const rl = @import("raylib");
const _ResourceManager = @import("../../managers/ResourceManager.zig");
const ResourceManager = _ResourceManager.ResourceManagerSingleton;
const Font = _ResourceManager.FONT;

pub const Window = struct {
    width: i32,
    height: i32,
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: rl.Color,

    pub fn draw(self: @This()) void {
        // rl.drawRectangleV(.{ .x = self.x, .y = self.y }, .{ .x = self.width, .y = self.height }, self.color);
        rl.drawRectangleRounded(.{ .x = self.x, .y = self.y, .width = self.width, .height = self.height }, 0.04, 6, self.color);
    }
};

pub const Text = struct {
    x: i32,
    y: i32,
    padding: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    value: [:0]const u8,
    fontSize: i32,
    color: rl.Color,

    pub fn getWidth(self: Text) i32 {
        return rl.measureText(self.value, self.fontSize);
    }

    pub fn draw(self: Text) void {
        // rl.drawText(
        //     self.value,
        //     self.x,
        //     self.y,
        //     self.fontSize,
        //     self.color,
        // );

        rl.drawTextEx(
            ResourceManager.getFont(Font.ROBOTO_REGULAR),
            self.value,
            .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) },
            @floatFromInt(self.fontSize),
            0,
            self.color,
        );
    }
};

pub fn Button() type {
    return struct {
        const Self = @This();

        rect: Rect,
        text: Text,
        mouseHover: bool = false,
        mouseClick: bool = false,

        pub fn init(text: [:0]const u8, x: f32, y: f32, fontSize: i32, rectColor: rl.Color, textColor: rl.Color) Self {
            const width: i32 = rl.measureText(text, fontSize);
            return .{
                .rect = .{
                    .x = x,
                    .y = y,
                    .width = @floatFromInt(width + 32),
                    .height = @floatFromInt(fontSize + 16),
                    .color = rectColor,
                },
                .text = .{
                    .value = text,
                    .x = @intFromFloat(x + 16),
                    .y = @intFromFloat(y + 8),
                    .fontSize = fontSize,
                    .color = textColor,
                },
            };
        }

        pub fn draw(self: @This()) void {
            self.rect.draw();
            self.text.draw();
            // rl.drawText(
            //     self.text.value,
            //     self.text.x,
            //     self.text.y,
            //     self.text.fontSize,
            //     self.text.color,
            // );
            //
            // rl.drawTextEx(
            //     ResourceManager.getFont(Font.ROBOTO_REGULAR),
            //     self.value,
            //     .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) },
            //     @floatFromInt(self.text.fontSize),
            //     0,
            //     self.color,
            // );
        }

        pub fn events(self: *Self) void {
            const mousePos: rl.Vector2 = rl.getMousePosition();

            if (mousePos.x > self.rect.x and mousePos.x < self.rect.x + self.rect.width and mousePos.y > self.rect.y and mousePos.y < self.rect.y + self.rect.height) {
                self.rect.color = .yellow;
                self.mouseHover = true;
            } else {
                self.rect.color = .white;
                self.mouseHover = false;
            }

            if (self.mouseHover == true and self.mouseClick == false) {
                if (rl.isMouseButtonPressed(.left)) {
                    self.rect.color = .gray;
                    self.mouseClick = true;
                }
            } else self.mouseClick = false;
        }
    };
}
