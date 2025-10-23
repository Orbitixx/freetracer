const std = @import("std");
const math = std.math;
const rl = @import("raylib");

const Debug = @import("freetracer-lib").Debug;

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const Rectangle = UIFramework.Rectangle;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElementCallbacks = UIFramework.UIElementCallbacks;

const Styles = @import("../Styles.zig");
const RectangleStyle = Styles.RectangleStyle;
const Color = Styles.Color;

const ResourceManagerImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceManagerImport.ResourceManagerSingleton;
const FontResource = ResourceManagerImport.FONT;

pub const TextStyle = struct {
    textColor: rl.Color = Color.white,
    font: FontResource = .ROBOTO_REGULAR,
    fontSize: f32 = 16,
    spacing: f32 = 0,
};

const Text = @This();
const MAX_TEXT_LENGTH = 256;

pub const Config = struct {
    identifier: ?UIElementIdentifier = null,
    callbacks: UIElementCallbacks = .{},
    pulsate: ?PulsateSettings = null,
    style: TextStyle = .{},
};

pub const PulsateSettings = struct {
    enabled: bool = false,
    duration: f32 = 1.5,
    /// Minimum alpha the pulsation should reach. Defaults to 0 (fully transparent).
    minAlpha: u8 = 0,
};

pub const PulsateState = struct {
    enabled: bool = false,
    duration: f32 = 1.5,
    minAlpha: u8 = 0,
    elapsed: f32 = 0,
};

identifier: ?UIElementIdentifier = null,
transform: Transform = .{},
textBuffer: [MAX_TEXT_LENGTH]u8,
style: TextStyle,
font: rl.Font,
background: ?Rectangle = null,
active: bool = true,

callbacks: UIElementCallbacks = .{},
pulsate: PulsateState = .{},

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
    if (!self.active) return;
    self.transform.resolve();

    if (self.pulsate.enabled) {
        const dt = rl.getFrameTime();
        if (self.pulsate.duration > 0) {
            self.pulsate.elapsed += dt;
            while (self.pulsate.elapsed >= self.pulsate.duration) {
                self.pulsate.elapsed -= self.pulsate.duration;
            }
        } else {
            self.pulsate.elapsed = 0;
        }
    }
}

pub fn draw(self: *Text) !void {
    if (!self.active) return;

    var drawColor = self.style.textColor;
    if (self.pulsate.enabled and self.pulsate.duration > 0) {
        self.clampPulsateAlpha();
        const baseAlpha: f32 = @floatFromInt(drawColor.a);
        const minAlpha: f32 = @floatFromInt(self.pulsate.minAlpha);
        const amplitude = baseAlpha - minAlpha;
        if (amplitude > 0) {
            const phase = if (self.pulsate.duration > 0) self.pulsate.elapsed / self.pulsate.duration else 0;
            const factor = (1 - math.cos(phase * math.tau)) * 0.5;
            const alpha = minAlpha + amplitude * factor;
            drawColor.a = @intFromFloat(math.clamp(alpha, 0.0, 255.0));
        } else {
            drawColor.a = @intFromFloat(math.clamp(minAlpha, 0.0, 255.0));
        }
    }

    rl.drawTextEx(
        self.font,
        @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00)),
        self.transform.positionAsVector2(),
        self.style.fontSize,
        self.style.spacing,
        drawColor,
    );
}

pub fn onEvent(self: *Text, event: UIEvent) void {
    // Debug.log(.DEBUG, "Text recevied a UIEvent: {any}", .{event});

    switch (event) {
        inline else => |e| if (e.target != self.identifier) return,
    }

    switch (event) {
        .TextChanged => |e| {
            if (e.text) |newText| self.setValue(newText);
            if (e.style) |style| self.style = style;
            if (e.pulsate) |pulsateState| self.pulsate = pulsateState;
            self.clampPulsateAlpha();
        },
        inline else => {},
    }
}

pub fn deinit(self: *Text) void {
    _ = self;
}

pub fn setValue(self: *Text, newValue: [:0]const u8) void {
    self.textBuffer = std.mem.zeroes([MAX_TEXT_LENGTH]u8);
    @memcpy(self.textBuffer[0..if (newValue.len > MAX_TEXT_LENGTH) MAX_TEXT_LENGTH else newValue.len], if (newValue.len > MAX_TEXT_LENGTH) newValue[0..MAX_TEXT_LENGTH] else newValue);
    const textDims: rl.Vector2 = rl.measureTextEx(self.font, @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00)), self.style.fontSize, self.style.spacing);
    self.transform.size = .pixels(textDims.x, textDims.y);
    self.transform.resolve();
}

pub fn setPulsate(self: *Text, settings: PulsateSettings) void {
    if (!settings.enabled) {
        self.pulsate = .{};
        return;
    }

    const duration = if (settings.duration <= 0) 1 else settings.duration;
    self.pulsate = .{
        .enabled = true,
        .duration = duration,
        .minAlpha = settings.minAlpha,
        .elapsed = 0,
    };
    self.clampPulsateAlpha();
}

fn clampPulsateAlpha(self: *Text) void {
    if (!self.pulsate.enabled) return;
    if (self.pulsate.minAlpha > self.style.textColor.a) {
        self.pulsate.minAlpha = self.style.textColor.a;
    }
}

// pub fn getDimensions(self: Text) TextDimensions {
//     const dims = rl.measureTextEx(self.font, self.value, self.style.fontSize, self.style.spacing);
//     return .{ .width = dims.x, .height = dims.y };
// }
