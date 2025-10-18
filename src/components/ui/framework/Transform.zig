const rl = @import("raylib");
const types = @import("./types.zig");

const RelativeRef = types.RelativeRef;
const PositionSpec = types.PositionSpec;
const SizeSpec = types.SizeSpec;
const TransformResolverFn = types.TransformResolverFn;

const Transform = @This();

x: f32 = 0,
y: f32 = 0,
w: f32 = 0,
h: f32 = 0,

position: PositionSpec = .{ .x = .{}, .y = .{} },
size: SizeSpec = .{ .width = .{}, .height = .{} },

scale: f32 = 1,
rotation: f32 = 0,

// TODO: Remove? Needed by GlobalTransform and section Views
relativeTransform: ?*const Transform = null,
position_ref: ?RelativeRef = .Parent,
size_ref: ?RelativeRef = .Parent,
position_ref_x: ?RelativeRef = null,
position_ref_y: ?RelativeRef = null,
size_ref_width: ?RelativeRef = null,
size_ref_height: ?RelativeRef = null,
position_transform_x: ?*const Transform = null,
position_transform_y: ?*const Transform = null,
size_transform_width: ?*const Transform = null,
size_transform_height: ?*const Transform = null,
// keep .relative as a "both" default for backward compatibility
relative: ?RelativeRef = .Parent,
_resolver_ctx: ?*const anyopaque = null,
_resolver_fn: ?TransformResolverFn = null,

offset_x: f32 = 0,
offset_y: f32 = 0,

inline fn rectZero() rl.Rectangle {
    return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
}
inline fn rectFromPtr(t: *const Transform) rl.Rectangle {
    return .{ .x = t.x, .y = t.y, .width = t.w * t.scale, .height = t.h * t.scale };
}
inline fn rectFromResolver(self: *Transform, rr: RelativeRef) rl.Rectangle {
    if (self._resolver_fn) |f| if (self._resolver_ctx) |ctx| return f(ctx, rr);
    return rectZero();
}
inline fn parentRect(self: *Transform) rl.Rectangle {
    if (self.relativeTransform) |p| return rectFromPtr(p);
    return rectFromResolver(self, .Parent);
}

inline fn rectFromRelative(self: *Transform, ref: RelativeRef) rl.Rectangle {
    return switch (ref) {
        .Parent => parentRect(self),
        .NodeId => |id| rectFromResolver(self, .{ .NodeId = id }),
    };
}

inline fn fallbackRect(self: *Transform) rl.Rectangle {
    if (self.relative) |r| return rectFromRelative(self, r);
    if (self.relativeTransform) |p| return rectFromPtr(p);
    return rectZero();
}

fn resolveReference(self: *Transform, override: ?RelativeRef, shared: ?RelativeRef, axis_transform: ?*const Transform) rl.Rectangle {
    if (axis_transform) |ptr| return rectFromPtr(ptr);
    if (override) |ref| return rectFromRelative(self, ref);
    if (shared) |ref| return rectFromRelative(self, ref);
    return fallbackRect(self);
}

pub fn resolve(self: *Transform) void {
    // --- choose reference rects for position (per axis) and size (per axis) ---
    const pos_ref_rect_x = resolveReference(self, self.position_ref_x, self.position_ref, self.position_transform_x);
    const pos_ref_rect_y = resolveReference(self, self.position_ref_y, self.position_ref, self.position_transform_y);

    const size_ref_rect_w = blk: {
        const rect = resolveReference(self, self.size_ref_width, self.size_ref, self.size_transform_width);
        if (rect.width == 0 and rect.height == 0 and self.size_ref_width == null and self.size_ref == null) {
            break :blk pos_ref_rect_x;
        }
        break :blk rect;
    };

    const size_ref_rect_h = blk: {
        const rect = resolveReference(self, self.size_ref_height, self.size_ref, self.size_transform_height);
        if (rect.width == 0 and rect.height == 0 and self.size_ref_height == null and self.size_ref == null) {
            break :blk pos_ref_rect_y;
        }
        break :blk rect;
    };

    // --- compute absolute frame ---
    self.w = self.size.width.resolve(size_ref_rect_w.width);
    self.h = self.size.height.resolve(size_ref_rect_h.height);
    self.x = pos_ref_rect_x.x + self.position.x.resolve(pos_ref_rect_x.width) + self.offset_x;
    self.y = pos_ref_rect_y.y + self.position.y.resolve(pos_ref_rect_y.height) + self.offset_y;
}

pub fn positionAsVector2(self: Transform) rl.Vector2 {
    return .{ .x = self.x, .y = self.y };
}
pub fn sizeAsVector2(self: Transform) rl.Vector2 {
    return .{ .x = self.w * self.scale, .y = self.h * self.scale };
}
pub fn asRaylibRectangle(self: Transform) rl.Rectangle {
    return .{ .x = self.x, .y = self.y, .width = self.w * self.scale, .height = self.h * self.scale };
}
