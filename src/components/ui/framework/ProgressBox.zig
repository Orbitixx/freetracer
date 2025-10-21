const std = @import("std");
const rl = @import("raylib");

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElementCallbacks = UIFramework.UIElementCallbacks;

const RectangleStyle = @import("../Styles.zig").RectangleStyle;

const ProgressBox = @This();

pub const Config = struct {
    identifier: ?UIElementIdentifier = null,
    backgroundStyle: RectangleStyle = .{},
    progressStyle: RectangleStyle = .{},
    progressPercent: f32 = 0,
    callbacks: UIElementCallbacks = .{},
};

identifier: ?UIElementIdentifier = null,
transform: Transform = .{},
backgroundStyle: RectangleStyle = .{},
progressStyle: RectangleStyle = .{},
callbacks: UIElementCallbacks = .{},
active: bool = true,

progressPercent: f32 = 0,
backgroundRect: rl.Rectangle = rectZero(),
progressRect: rl.Rectangle = rectZero(),
layoutDirty: bool = true,

pub fn init(config: Config) ProgressBox {
    return .{
        .identifier = config.identifier,
        .backgroundStyle = config.backgroundStyle,
        .progressStyle = config.progressStyle,
        .callbacks = config.callbacks,
        .progressPercent = clampPercent(config.progressPercent),
    };
}

pub fn start(self: *ProgressBox) !void {
    self.transform.resolve();
    self.updateRects();
    self.layoutDirty = false;
}

pub fn update(self: *ProgressBox) !void {
    if (!self.active) return;

    self.transform.resolve();
    const rect = self.transform.asRaylibRectangle();

    if (!rectEquals(rect, self.backgroundRect) or self.layoutDirty) {
        self.backgroundRect = rect;
        self.updateProgressRect();
        self.layoutDirty = false;
    }
}

pub fn draw(self: *ProgressBox) !void {
    if (!self.active) return;

    drawStyledRect(self.backgroundRect, self.backgroundStyle);

    if (self.progressRect.width > 0.0 and self.progressRect.height > 0.0 and self.progressPercent > 0.0) {
        drawStyledRect(self.progressRect, self.progressStyle);
    }
}

pub fn onEvent(self: *ProgressBox, event: UIEvent) void {
    switch (event) {
        .ProgressValueChanged => |payload| {
            if (payload.target) |target| {
                if (self.identifier == null or self.identifier.? != target) return;
            }

            const percent_f = @as(f32, @floatFromInt(payload.percent));
            self.setProgressPercent(percent_f);
        },
        else => {},
    }
}

pub fn deinit(self: *ProgressBox) void {
    _ = self;
}

fn setProgressPercent(self: *ProgressBox, percent: f32) void {
    const clamped = clampPercent(percent);
    if (@abs(self.progressPercent - clamped) < 0.01) return;

    self.progressPercent = clamped;
    self.layoutDirty = true;
}

fn updateRects(self: *ProgressBox) void {
    self.backgroundRect = self.transform.asRaylibRectangle();
    self.updateProgressRect();
}

fn updateProgressRect(self: *ProgressBox) void {
    const clamped = clampPercent(self.progressPercent);
    const fraction = clamped / 100.0;

    const width = self.backgroundRect.width * fraction;
    self.progressRect = .{
        .x = self.backgroundRect.x,
        .y = self.backgroundRect.y,
        .width = if (width < 0.0) 0.0 else width,
        .height = self.backgroundRect.height,
    };
}

fn clampPercent(input: f32) f32 {
    return std.math.clamp(input, 0.0, 100.0);
}

fn drawStyledRect(rect: rl.Rectangle, style: RectangleStyle) void {
    if (style.roundness <= 0.0) {
        rl.drawRectangleRec(rect, style.color);
        if (style.borderStyle.thickness > 0) {
            rl.drawRectangleLinesEx(rect, style.borderStyle.thickness, style.borderStyle.color);
        }
        return;
    }

    rl.drawRectangleRounded(
        rect,
        if (style.roundness <= 0.0) 0.001 else style.roundness,
        if (style.segments <= 0) 6 else style.segments,
        style.color,
    );

    if (style.borderStyle.thickness > 0) {
        rl.drawRectangleRoundedLinesEx(
            rect,
            if (style.roundness <= 0.0) 0.001 else style.roundness,
            if (style.segments <= 0) 6 else style.segments,
            style.borderStyle.thickness,
            style.borderStyle.color,
        );
    }
}

fn rectZero() rl.Rectangle {
    return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
}

fn rectEquals(a: rl.Rectangle, b: rl.Rectangle) bool {
    const epsilon = 0.25;
    return @abs(a.x - b.x) < epsilon and @abs(a.y - b.y) < epsilon and @abs(a.width - b.width) < epsilon and @abs(a.height - b.height) < epsilon;
}
