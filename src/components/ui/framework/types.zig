const std = @import("std");
const rl = @import("raylib");

// A reference target that is stable across reallocations within a View's ArrayList
pub const RelativeRef = union(enum) {
    Parent,
    NodeId: []const u8, // string id local to the containing View
};

// A small “resolver” hook so Transform can ask its owner where a RelativeRef points.
// We use an opaque context pointer to avoid circular type dependencies.
pub const TransformResolverFn = *const fn (ctx: *const anyopaque, ref: RelativeRef) rl.Rectangle;

pub const UnitValue = struct {
    perc: f32 = 0, // 0.0 - 1.0
    px: f32 = 0,

    pub fn pixels(value: f32) UnitValue {
        return .{ .px = value };
    }

    pub fn percent(value: f32) UnitValue {
        return .{ .perc = value };
    }

    pub fn mix(_percent: f32, _pixels: f32) UnitValue {
        return .{ .perc = _percent, .px = _pixels };
    }

    pub fn resolve(self: UnitValue, reference: f32) f32 {
        return reference * self.perc + self.px;
    }
};

pub const PositionSpec = struct {
    x: UnitValue = .{},
    y: UnitValue = .{},

    pub fn pixels(x: f32, y: f32) PositionSpec {
        return .{ .x = UnitValue.pixels(x), .y = UnitValue.pixels(y) };
    }

    pub fn percent(x: f32, y: f32) PositionSpec {
        return .{ .x = UnitValue.percent(x), .y = UnitValue.percent(y) };
    }

    pub fn mix(x: UnitValue, y: UnitValue) PositionSpec {
        return .{ .x = x, .y = y };
    }
};

pub const SizeSpec = struct {
    width: UnitValue = UnitValue.percent(1),
    height: UnitValue = UnitValue.percent(1),

    pub fn pixels(width: f32, height: f32) SizeSpec {
        return .{ .width = UnitValue.pixels(width), .height = UnitValue.pixels(height) };
    }

    pub fn percent(width: f32, height: f32) SizeSpec {
        return .{ .width = UnitValue.percent(width), .height = UnitValue.percent(height) };
    }

    pub fn mix(width: UnitValue, height: UnitValue) SizeSpec {
        return .{ .width = width, .height = height };
    }
};
