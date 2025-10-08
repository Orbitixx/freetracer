const std = @import("std");
const AppConfig = @import("../../config.zig");
const UIFramework = @import("./import/index.zig");
const Text = UIFramework.Primitives.Text;
const Rectangle = UIFramework.Primitives.Rectangle;
const Transform = UIFramework.Primitives.Transform;
const Statusbox = UIFramework.Statusbox;

const EMPTY_TEXT: [:0]const u8 = &[_:0]u8{0};

const SECTION_PADDING: f32 = AppConfig.APP_UI_MODULE_SECTION_PADDING;

pub const ProgressBox = struct {
    value: u64 = 0,
    text: Text = undefined,
    percentTextBuf: [5]u8 = undefined,
    percentText: Text = undefined,
    rect: Rectangle = undefined,

    pub fn draw(self: *ProgressBox) void {
        self.text.draw();
        self.percentText.draw();
        self.rect.draw();
    }

    pub fn setProgressTo(self: *ProgressBox, referenceRect: Rectangle, newValue: u64) void {
        const clamped = std.math.clamp(newValue, @as(u64, 0), @as(u64, 100));
        self.value = clamped;

        const width: f32 = referenceRect.transform.getWidth();
        const percent_f32: f32 = @floatFromInt(clamped);
        const percent_u8: u8 = @intCast(clamped);
        self.percentTextBuf = std.mem.zeroes([5]u8);
        self.percentText.value = std.fmt.bufPrintZ(self.percentTextBuf[0..], "{d}%", .{percent_u8}) catch EMPTY_TEXT;
        self.rect.transform.w = (percent_f32 / 100.0) * (1 - SECTION_PADDING) * width;
    }
};

pub const StatusIndicator = struct {
    text: Text = undefined,
    box: Statusbox = undefined,

    pub fn init(text: [:0]const u8, size: f32) StatusIndicator {
        var statusBox = Statusbox.init(.{ .x = 0, .y = 0 }, size, .Primary);
        statusBox.switchState(.NONE);

        return StatusIndicator{
            .text = Text.init(text, .{ .x = 0, .y = 0 }, .{ .fontSize = 14 }),
            .box = statusBox,
        };
    }

    pub fn switchState(self: *StatusIndicator, newState: Statusbox.StatusboxState) void {
        self.box.switchState(newState);
    }

    pub fn calculateUI(self: *StatusIndicator, transform: Transform) void {
        self.text.transform.x = transform.x;
        self.text.transform.y = transform.y + transform.h / 2 - self.text.getDimensions().height / 2;
        self.box.setPosition(.{ .x = transform.x + transform.w - transform.h, .y = transform.y });
    }

    pub fn draw(self: *StatusIndicator) !void {
        self.text.draw();
        try self.box.draw();
    }
};
