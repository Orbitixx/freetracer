const std = @import("std");
const rl = @import("raylib");
const UI = @import("../ui/ui.zig");

const Event = @import("../../observers/AppObserver.zig").Event;
const Payload = @import("../../observers/AppObserver.zig").Payload;
const USBDevicesListComponent = @import("../../components/USBDevicesList/Component.zig");

const INNER_PADDING = 2;

pub fn Checkbox() type {
    return struct {
        const Self = @This();

        onSelected: ?*const fn (component: *anyopaque, event: Event, payload: Payload) void = null,
        context: ?*anyopaque = null,
        data: ?[]u8 = null,

        rect: UI.Rect,
        text: UI.Text,
        checked: bool = false,
        pressed: bool = false,
        hovered: bool = false,

        pub fn init(text: [:0]const u8, x: f32, y: f32, size: f32) Self {
            const fontSize: f32 = 14;

            return .{
                .rect = .{
                    .x = x,
                    .y = y,
                    .width = size,
                    .height = size,
                    .color = rl.Color.white,
                },

                .text = .{
                    .x = x + size + 4,
                    .y = y + (size / 2) - fontSize / 2,
                    .value = text,
                    .fontSize = fontSize,
                    .color = rl.Color.white,
                },
            };
        }

        pub fn update(self: *Self) void {
            const mousePos: rl.Vector2 = rl.getMousePosition();

            const totalBounds: rl.Rectangle = .{
                .x = self.rect.x,
                .y = self.rect.y,
                .width = self.rect.width + self.text.getWidth() + self.text.padding.x + self.text.padding.width,
                .height = self.rect.height,
            };

            // Check HOVERED state
            if (rl.checkCollisionPointRec(mousePos, totalBounds))
                self.hovered = true
            else
                self.hovered = false;

            // Check PRESSED ONCE state and dispatch CHECKED state
            if (self.hovered and !self.pressed) {
                if (rl.isMouseButtonPressed(.left)) {
                    self.pressed = true;
                }
            } else self.pressed = false;

            // Toggle CHECKED state on press
            if (self.pressed)
                self.checked = !self.checked;

            if (self.checked and self.pressed) {
                self.onSelected.?(self.context.?, Event.USB_DEVICE_SELECTED, Payload{ .data = self.data.? });
            }
        }

        pub fn draw(self: *Self) void {
            if (self.hovered) {
                self.rect.color = .sky_blue;
                self.text.color = .sky_blue;
            } else {
                self.rect.color = .white;
                self.text.color = .white;
            }

            self.rect.draw();
            self.text.draw();

            if (self.checked) {
                const innerRect: UI.Rect = .{
                    .x = self.rect.x + INNER_PADDING,
                    .y = self.rect.y + INNER_PADDING,
                    .width = self.rect.width - INNER_PADDING * 2,
                    .height = self.rect.height - INNER_PADDING * 2,
                    .color = .black,
                };

                innerRect.draw();
            }
        }
    };
}
