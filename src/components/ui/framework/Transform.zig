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
relativeRef: ?*const Transform = null,
position_ref: ?RelativeRef = .Parent,
size_ref: ?RelativeRef = .Parent,
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
    if (self.relativeRef) |p| return rectFromPtr(p);
    return rectFromResolver(self, .Parent);
}

pub fn resolve(self: *Transform) void {
    // --- choose reference rects for position and size ---
    const pos_ref_rect: rl.Rectangle = blk: {
        if (self.position_ref) |pr| switch (pr) {
            .Parent => break :blk parentRect(self),
            .NodeId => |id| break :blk rectFromResolver(self, .{ .NodeId = id }),
        };
        if (self.relative) |r| switch (r) {
            .Parent => break :blk parentRect(self),
            .NodeId => |id| break :blk rectFromResolver(self, .{ .NodeId = id }),
        };
        if (self.relativeRef) |p| break :blk rectFromPtr(p);
        break :blk rectZero();
    };

    const size_ref_rect: rl.Rectangle = blk: {
        if (self.size_ref) |sr| switch (sr) {
            .Parent => break :blk parentRect(self),
            .NodeId => |id| break :blk rectFromResolver(self, .{ .NodeId = id }),
        };
        if (self.relative) |r| switch (r) {
            .Parent => break :blk parentRect(self),
            .NodeId => |id| break :blk rectFromResolver(self, .{ .NodeId = id }),
        };
        if (self.relativeRef) |p| break :blk rectFromPtr(p);
        // fallback: size against whatever we used for position
        break :blk pos_ref_rect;
    };

    // --- compute absolute frame ---
    self.w = self.size.width.resolve(size_ref_rect.width);
    self.h = self.size.height.resolve(size_ref_rect.height);
    self.x = pos_ref_rect.x + self.position.x.resolve(pos_ref_rect.width) + self.offset_x;
    self.y = pos_ref_rect.y + self.position.y.resolve(pos_ref_rect.height) + self.offset_y;
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
