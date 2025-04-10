const std = @import("std");
const rl = @import("raylib");
const osd = @import("osdialog");

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: rl.Color,

    pub fn draw(self: @This()) void {
        rl.drawRectangleV(.{ .x = self.x, .y = self.y }, .{ .x = self.width, .y = self.height }, self.color);
    }
};

pub const Text = struct {
    x: i32,
    y: i32,
    value: [:0]const u8,
    fontSize: i32,
    color: rl.Color,
};

pub fn Button() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        pPath: *?[]u8,
        rect: Rect,
        text: Text,
        action: *const fn (allocator: std.mem.Allocator, action: osd.PathAction, options: osd.PathOptions) ?[:0]u8,
        mouseHover: bool = false,

        pub fn init(allocator: std.mem.Allocator, pPath: *?[]u8, text: [:0]const u8, x: f32, y: f32, fontSize: i32, rectColor: rl.Color, textColor: rl.Color) Self {
            const width: i32 = rl.measureText(text, fontSize);
            return .{
                .allocator = allocator,
                .pPath = pPath,
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
                .action = osd.path,
            };
        }

        pub fn draw(self: @This()) void {
            self.rect.draw();
            rl.drawText(
                self.text.value,
                self.text.x,
                self.text.y,
                self.text.fontSize,
                self.text.color,
            );
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

            if (self.mouseHover == true) {
                if (rl.isMouseButtonPressed(.left)) {
                    self.rect.color = .gray;

                    if (self.action(self.allocator, .open, .{})) |path| {
                        defer self.allocator.free(path);

                        if (self.allocator.dupe(u8, path)) |dupedPath| {
                            self.pPath.* = dupedPath;
                        } else |_| {
                            std.debug.print("\nERROR: unabaled to allocate memory for selected file path!", .{});
                        }
                    }
                }
            }
        }

        pub fn deinit(self: Self) void {
            if (self.pPath.* != null)
                self.allocator.free(self.pPath.*.?);
        }
    };
}
