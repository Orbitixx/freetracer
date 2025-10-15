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

pub fn resolve(self: *Transform) void {
    // 1) Choose the reference rectangle
    const ref_rect = blk: {
        // Legacy pointer path first (for backward compatibility)
        if (self.relativeRef) |r| {
            break :blk rl.Rectangle{
                .x = r.x,
                .y = r.y,
                .width = r.w * r.scale,
                .height = r.h * r.scale,
            };
        }

        if (self.relative) |rr| {
            if (self._resolver_fn) |f| {
                if (self._resolver_ctx) |ctx| {
                    break :blk f(ctx, rr);
                }
            }
        }

        // Fallback: no ref -> resolve against origin with zero size
        break :blk rl.Rectangle{ .x = 0, .y = 0, .width = self.w + self.scale, .height = self.h * self.scale };
    };

    // 2) Compute absolute frame
    const pos_ref_rect = if (self.position_ref) |pr| blk: {
        break :blk self._resolver_fn.?(self._resolver_ctx.?, pr);
    } else if (self.relative) |r| blk: {
        break :blk self._resolver_fn.?(self._resolver_ctx.?, r);
    } else ref_rect; // from legacy or fallback

    const size_ref_rect = if (self.size_ref) |sr| self._resolver_fn.?(self._resolver_ctx.?, sr) else if (self.relative) |r| self._resolver_fn.?(self._resolver_ctx.?, r) else ref_rect;

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
