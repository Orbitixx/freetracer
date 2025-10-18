//
const rl = @import("raylib");
const Layout = @import("./Layout.zig");
const UnitValue = Layout.UnitValue;
const PositionSpec = Layout.PositionSpec;
const SizeSpec = Layout.SizeSpec;

const Transform = @This();

x: f32 = 0,
y: f32 = 0,
w: f32 = 0,
h: f32 = 0,

position: PositionSpec = .{
    .x = .{},
    .y = .{},
},

size: SizeSpec = .{
    .width = .{},
    .height = .{},
},

scale: f32 = 1,
rotation: f32 = 0,
relativeTransform: ?*const Transform = null,

pub fn resolve(self: *Transform) void {
    const ref = self.relativeTransform;

    self.x = (if (ref) |r| r.x else 0) + self.position.x.resolve(if (ref) |r| r.w else 0);
    self.y = (if (ref) |r| r.y else 0) + self.position.y.resolve(if (ref) |r| r.h else 0);

    self.w = self.size.width.resolve(if (ref) |r| r.w else 0);
    self.h = self.size.height.resolve(if (ref) |r| r.h else 0);
}

pub fn positionAsVector2(self: Transform) rl.Vector2 {
    return .{
        .x = self.x,
        .y = self.y,
    };
}

pub fn sizeAsVector2(self: Transform) rl.Vector2 {
    return .{
        .x = self.w,
        .y = self.h,
    };
}

pub fn asRaylibRectangle(self: Transform) rl.Rectangle {
    return .{
        .x = self.x,
        .y = self.y,
        .width = self.w,
        .height = self.h,
    };
}
