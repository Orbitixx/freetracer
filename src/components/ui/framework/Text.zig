const std = @import("std");
const rl = @import("raylib");

const Debug = @import("freetracer-lib").Debug;

const Transform = @import("./Transform.zig");
const Rectangle = @import("./Rectangle.zig");

const Event = @import("./UIEvent.zig");
const UIEvent = Event.UIEvent;
const UIElementIdentifier = Event.UIElementIdentifier;

const Styles = @import("../Styles.zig");
const RectangleStyle = Styles.RectangleStyle;
const TextStyle = Styles.TextStyle;
const Color = Styles.Color;

const ResourceManagerImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceManagerImport.ResourceManagerSingleton;

const Text = @This();
const MAX_TEXT_LENGTH = 256;

identifier: ?UIElementIdentifier = null,
transform: Transform = .{},
textBuffer: [MAX_TEXT_LENGTH]u8,
style: TextStyle,
font: rl.Font,
background: ?Rectangle = null,

pub fn init(identifier: ?UIElementIdentifier, value: [:0]const u8, transform: Transform, style: TextStyle) Text {
    if (value.len > MAX_TEXT_LENGTH) Debug.log(
        .WARNING,
        "Text UIElement's value length exceeded allowed max: {s}",
        .{value},
    );

    var textValue: [MAX_TEXT_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_LENGTH]u8);
    @memcpy(
        textValue[0..if (value.len > MAX_TEXT_LENGTH) MAX_TEXT_LENGTH else value.len],
        if (value.len > MAX_TEXT_LENGTH) value[0..MAX_TEXT_LENGTH] else value,
    );

    return .{
        .identifier = identifier,
        .transform = transform,
        .textBuffer = textValue,
        .style = style,
        .font = ResourceManager.getFont(style.font),
    };
}

pub fn start(self: *Text) !void {
    self.transform.resolve();
    const textDims: rl.Vector2 = rl.measureTextEx(self.font, @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00)), self.style.fontSize, self.style.spacing);
    self.transform.size = .pixels(textDims.x, textDims.y);
}

pub fn update(self: *Text) !void {
    self.transform.resolve();
}

pub fn draw(self: *Text) !void {
    rl.drawTextEx(
        self.font,
        @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00)),
        self.transform.positionAsVector2(),
        self.style.fontSize,
        self.style.spacing,
        self.style.textColor,
    );
}

pub fn onEvent(self: *Text, event: UIEvent) void {
    Debug.log(.DEBUG, "Text recevied a UIEvent: {any}", .{event});

    switch (event) {
        inline else => |e| if (e.target != self.identifier) return,
    }

    switch (event) {
        .TextChanged => |e| {
            self.setValue(e.text);
        },
    }
}

pub fn deinit(self: *Text) void {
    _ = self;
}

pub fn setValue(self: *Text, newValue: [:0]const u8) void {
    self.textBuffer = std.mem.zeroes([MAX_TEXT_LENGTH]u8);
    @memcpy(self.textBuffer[0..if (newValue.len > MAX_TEXT_LENGTH) MAX_TEXT_LENGTH else newValue.len], if (newValue.len > MAX_TEXT_LENGTH) newValue[0..MAX_TEXT_LENGTH] else newValue);
}

// pub fn getDimensions(self: Text) TextDimensions {
//     const dims = rl.measureTextEx(self.font, self.value, self.style.fontSize, self.style.spacing);
//     return .{ .width = dims.x, .height = dims.y };
// }
