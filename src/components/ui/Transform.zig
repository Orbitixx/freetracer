//
//
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
relativeRef: ?*const Transform = null,

pub fn resolve(self: *Transform) void {
    const ref = self.relativeRef;

    self.x = (if (ref) |r| r.x else 0) + self.position.x.resolve(if (ref) |r| r.w else 0);
    self.y = (if (ref) |r| r.y else 0) + self.position.y.resolve(if (ref) |r| r.h else 0);

    self.w = self.size.width.resolve(if (ref) |r| r.w else 0);
    self.h = self.size.height.resolve(if (ref) |r| r.h else 0);
}
