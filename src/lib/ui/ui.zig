const std = @import("std");
const rl = @import("raylib");
const _ResourceManager = @import("../../managers/ResourceManager.zig");
const ResourceManager = _ResourceManager.ResourceManagerSingleton;
const Font = _ResourceManager.FONT;

pub const Window = struct {
    width: i32,
    height: i32,
};

pub const UIRectangle = struct {
    transform: Rectangle,
    color: rl.Color,

    pub fn draw(self: UIRectangle) void {
        rl.drawRectangleRounded(self.transform.toRaylibRectangle(), 0.2, 6, self.color);
    }
};

pub const Text = struct {
    x: f32,
    y: f32,
    padding: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    value: [:0]const u8,
    fontSize: f32,
    color: rl.Color,

    pub fn getWidth(self: Text) f32 {
        // TODO: Fix casts by using measureTextEx
        return @floatFromInt(rl.measureText(self.value, @as(i32, @intFromFloat(self.fontSize))));
    }

    pub fn draw(self: Text) void {
        rl.drawTextEx(
            ResourceManager.getFont(Font.ROBOTO_REGULAR),
            self.value,
            .{ .x = self.x, .y = self.y },
            self.fontSize,
            0,
            self.color,
        );
    }
};

pub const Rectangle = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    /// Returns absolute X coordinate relative to the Rectange's position and width
    pub fn relW(self: Rectangle, x: f32) f32 {
        return self.x + self.w * x;
    }

    /// Returns absolute X coordinate relative to the Rectange's position and width
    pub fn relH(self: Rectangle, y: f32) f32 {
        return self.y + self.h * y;
    }

    pub fn toRaylibRectangle(self: Rectangle) rl.Rectangle {
        return rl.Rectangle{ .x = self.x, .y = self.y, .width = self.w, .height = self.h };
    }
};

const BUTTON_PADDING: f32 = 16;

pub const ButtonState = enum {
    NORMAL,
    HOVER,
    ACTIVE,
};

pub const ButtonColorVariant = struct {
    rect: rl.Color,
    text: rl.Color,
};

pub const ButtonColorVariants = struct {
    normal: ButtonColorVariant,
    hover: ButtonColorVariant,
    active: ButtonColorVariant,
};

pub fn Button() type {
    return struct {
        const Self = @This();

        rect: UIRectangle,
        text: Text,
        state: ButtonState = ButtonState.NORMAL,
        variants: ButtonColorVariants,
        hasShadow: bool = false,

        pub fn init(text: [:0]const u8, x: f32, y: f32, fontSize: f32, variants: ButtonColorVariants) Self {
            // const textDimensions = rl.measureTextEx(ResourceManager.getFont(Font.ROBOTO_REGULAR), text, fontSize, 0);

            const textWidth = rl.measureText(text, @as(i32, @intFromFloat(fontSize)));

            const rect: UIRectangle = .{
                .transform = .{
                    .x = x,
                    .y = y,
                    .w = @as(f32, @floatFromInt(textWidth)) + BUTTON_PADDING * 2,
                    .h = fontSize + BUTTON_PADDING,
                },
                .color = .white,
            };

            return .{
                .rect = rect,

                .text = .{
                    .value = text,
                    .x = rect.transform.relW(0.5) - @as(f32, @floatFromInt(@divTrunc(textWidth, 2))),
                    .y = rect.transform.relH(0.5) - @divTrunc(fontSize, 2),
                    .fontSize = fontSize,
                    .color = .black,
                },

                .variants = variants,
            };
        }

        pub fn draw(self: Self) void {
            // if (self.hasShadow) rl.drawRectangleRounded(.{
            //     .x = self.rect.transform.x + 3,
            //     .y = self.rect.transform.y + 3,
            //     .width = self.rect.transform.w,
            //     .height = self.rect.transform.h,
            // }, 0.2, 6, .black);

            self.rect.draw();
            self.text.draw();
        }

        pub fn events(self: *Self) void {
            const mousePos: rl.Vector2 = rl.getMousePosition();
            const isButtonClicked: bool = rl.isMouseButtonPressed(.left);
            const isButtonHovered: bool = rl.checkCollisionPointRec(mousePos, self.rect.transform.toRaylibRectangle());

            if (isButtonHovered and isButtonClicked) {
                self.state = ButtonState.ACTIVE;
            } else if (isButtonHovered) {
                self.state = ButtonState.HOVER;
            } else {
                self.state = ButtonState.NORMAL;
            }

            switch (self.state) {
                .HOVER => {
                    self.rect.color = self.variants.hover.rect;
                    self.text.color = self.variants.hover.text;
                },
                .ACTIVE => {
                    self.rect.color = self.variants.active.rect;
                    self.text.color = self.variants.active.text;
                },
                .NORMAL => {
                    self.rect.color = self.variants.normal.rect;
                    self.text.color = self.variants.normal.text;
                },
            }
        }

        pub fn setPosition(self: *Self, x: f32, y: f32) void {
            self.rect.transform.x = x;
            self.rect.transform.y = y;

            self.text.x = x + BUTTON_PADDING;
            self.text.y = y + BUTTON_PADDING / 2;
        }
    };
}
