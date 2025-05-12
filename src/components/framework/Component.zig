const ComponentState = @import("./import/index.zig").ComponentState;

// pub fn Component(comptime StateType: type) type {
//     return struct {
//         const Self = @This();
//
//         state: *ComponentState(StateType),
//         vtable: *const VTable,
//         context: ?*anyopaque,
//
//         pub const VTable = struct {
//             init_fn: fn (*Self) anyerror!void,
//             deinit_fn: fn (*Self) void,
//             update_fn: fn (*Self) anyerror!void,
//             draw_fn: fn (*Self) anyerror!void,
//         };
//
//         pub fn init(
//             state: *ComponentState(StateType),
//             vtable: *const VTable,
//             context: ?*anyopaque,
//         ) Self {
//             return .{
//                 .state = state,
//                 .vtable = vtable,
//                 .context = context,
//             };
//         }
//
//         pub fn initComponent(self: *Self) !void {
//             return self.vtable.init_fn(self);
//         }
//
//         pub fn deinit(self: *Self) void {
//             self.vtable.deinit_fn(self);
//         }
//
//         pub fn update(self: *Self) !void {
//             return self.vtable.update_fn(self);
//         }
//
//         pub fn draw(self: *Self) !void {
//             return self.vtable.draw_fn(self);
//         }
//     };
// }

// Generic Component interface
pub const GenericComponent = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init_fn: fn (ptr: *anyopaque) anyerror!void,
        deinit_fn: fn (ptr: *anyopaque) void,
        update_fn: fn (ptr: *anyopaque) anyerror!void,
        draw_fn: fn (ptr: *anyopaque) anyerror!void,
    };

    pub fn init(ptr: *anyopaque, vtable: *const VTable) GenericComponent {
        return .{ .ptr = ptr, .vtable = vtable };
    }

    pub fn initComponent(self: GenericComponent) !void {
        return self.vtable.init_fn(self.ptr);
    }

    pub fn deinit(self: GenericComponent) void {
        self.vtable.deinit_fn(self.ptr);
    }

    pub fn update(self: GenericComponent) !void {
        return self.vtable.update_fn(self.ptr);
    }

    pub fn draw(self: GenericComponent) !void {
        return self.vtable.draw_fn(self.ptr);
    }
};
