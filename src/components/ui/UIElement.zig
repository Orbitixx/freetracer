const std = @import("std");
const Debug = @import("freetracer-lib").Debug;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Primitives = @import("./Primitives.zig");
const Rectangle = Primitives.RectanglePro;
const Text = Primitives.Text;
const Texture = Primitives.Texture;
const Button = @import("./Button.zig");
const SpriteButton = @import("./SpriteButton.zig");
const Transform = @import("./Transform.zig");

const Layout = @import("./Layout.zig");
const Bounds = Layout.Bounds;

pub fn autoVTable(comptime VTableType: type, comptime ImplType: type) VTableType {
    var vt: VTableType = undefined;

    inline for (@typeInfo(VTableType).@"struct".fields) |field| {
        // Each vtable field is a pointer-to-fn like *const fn(*anyopaque) <Ret>
        const ptr_info = @typeInfo(field.type).pointer;
        const fn_info = @typeInfo(ptr_info.child).@"fn";

        // The concrete method on ImplType (e.g. update/draw/deinit)
        const method = @field(ImplType, field.name);

        // We generate a thunk with the *same* signature as the vtable field:
        // fn(*anyopaque) ReturnType
        const ReturnType = fn_info.return_type.?;

        const Thunk = struct {
            fn call(p: *anyopaque) ReturnType {
                const self: *ImplType = @ptrCast(@alignCast(p));
                // Call the concrete method; this compiles whether ReturnType is void or anyerror!void.
                return @call(.auto, method, .{self});
            }
        };

        @field(vt, field.name) = &Thunk.call;
    }
    return vt;
}

pub const UIElement = struct {
    ptr: *anyopaque = undefined,
    vtable: *const VTable,

    pub const VTable = struct {
        start: *const fn (*anyopaque) anyerror!void,
        update: *const fn (*anyopaque) anyerror!void,
        draw: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn start(self: *UIElement) !void {
        return self.vtable.start(self.ptr);
    }

    pub fn update(self: *UIElement) !void {
        return self.vtable.update(self.ptr);
    }

    pub fn draw(self: *UIElement) !void {
        return self.vtable.draw(self.ptr);
    }

    pub fn deinit(self: *UIElement) void {
        return self.vtable.deinit(self.ptr);
    }
};

pub const ElementWrapper = union(enum) {
    View: View,

    pub fn start(self: *ElementWrapper) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).start(),
        }
    }

    pub fn update(self: *ElementWrapper) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).update(),
        }
    }

    pub fn draw(self: *ElementWrapper) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).draw(),
        }
    }

    pub fn deinit(self: *ElementWrapper) void {
        switch (self.*) {
            inline else => |*element| @constCast(element).deinit(),
        }
    }

    pub fn asElementPointer(self: *ElementWrapper) *UIElement {
        switch (self.*) {
            inline else => |*element| return @constCast(element).asElementPtr(),
        }
    }
};

pub const View = struct {
    const vtable: UIElement.VTable = autoVTable(UIElement.VTable, View);

    element: UIElement = .{ .vtable = &vtable },

    allocator: Allocator,
    transform: Transform = .{},
    background: ?Rectangle = null,
    children: ArrayList(ElementWrapper),

    pub fn init(allocator: Allocator, transform: Transform, background: ?Rectangle) View {
        return .{
            .allocator = allocator,
            .transform = transform,
            .background = background,
            .children = ArrayList(ElementWrapper).empty,
        };
    }

    pub fn addChild(self: *View, child: ElementWrapper) !void {
        try self.children.append(self.allocator, child);
    }

    pub fn start(self: *View) !void {
        Debug.log(.DEBUG, "View start() called.", .{});
        self.element.ptr = self;

        self.layoutSelf();

        for (self.children.items) |*child| {
            try child.start();
        }
    }

    fn layoutSelf(self: *View) void {
        _ = self.transform.resolve();
        if (self.background) |*bg| {
            bg.transform = self.transform;
        }
    }

    pub fn update(self: *View) !void {
        self.layoutSelf();
        for (self.children.items) |*child| {
            try child.update();
        }
    }

    pub fn draw(self: *View) !void {
        if (self.background) |*bg| bg.draw();

        for (self.children.items) |*child| {
            try child.draw();
        }
    }

    pub fn deinit(self: *View) void {
        for (self.children.items) |*child| {
            child.deinit();
        }

        self.children.deinit(self.allocator);
    }

    pub fn asElementPtr(self: *View) *UIElement {
        return &self.element;
    }
};

// pub const View = struct {
//     const EmptyChildren = std.meta.Tuple(&.{});
//
//     pub fn init(frame: Bounds, background: ?Rectangle, children_input: anytype) Instance(NormalizedChildrenType(@TypeOf(children_input))) {
//         const normalized = normalizeChildren(children_input);
//         return Instance(@TypeOf(normalized)).init(frame, background, normalized);
//     }
//
//     fn Instance(comptime ChildrenType: type) type {
//         return struct {
//             const Self = @This();
//
//             const VTableHolder = struct {
//                 pub const value = autoVTable(UIElement.VTable, Self);
//             };
//
//             frame: Bounds,
//             background: ?Rectangle = null,
//             children: ChildrenType,
//
//             pub fn init(frame: Bounds, background: ?Rectangle, children: ChildrenType) Self {
//                 return .{
//                     .frame = frame,
//                     .background = background,
//                     .children = children,
//                 };
//             }
//
//             pub fn asElement(self: *Self) UIElement {
//                 return .{
//                     .ptr = @as(*anyopaque, @ptrCast(self)),
//                     .vtable = &VTableHolder.value,
//                 };
//             }
//
//             pub fn start(self: *Self) !void {
//                 try iterateChildren(self, "start", true);
//             }
//
//             pub fn update(self: *Self) !void {
//                 try iterateChildren(self, "update", true);
//             }
//
//             pub fn draw(self: *Self) !void {
//                 if (self.background) |*bg| bg.draw();
//                 try iterateChildren(self, "draw", false);
//             }
//
//             pub fn deinit(self: *Self) void {
//                 iterateChildrenVoid(self, "deinit");
//             }
//
//             fn iterateChildren(self: *Self, comptime method: []const u8, comptime optional: bool) !void {
//                 inline for (@typeInfo(ChildrenType).@"struct".fields) |field| {
//                     const child_ptr = &@field(self.children, field.name);
//                     try callMethod(child_ptr, method, optional);
//                 }
//             }
//
//             fn iterateChildrenVoid(self: *Self, comptime method: []const u8) void {
//                 inline for (@typeInfo(ChildrenType).@"struct".fields) |field| {
//                     const child_ptr = &@field(self.children, field.name);
//                     callMethodVoid(child_ptr, method);
//                 }
//             }
//         };
//     }
//
//     fn NormalizedChildrenType(comptime T: type) type {
//         return switch (@typeInfo(T)) {
//             @typeInfo(@TypeOf(null)) => EmptyChildren,
//             .@"struct" => |info| if (info.is_tuple) T else std.meta.Tuple(&.{T}),
//             else => std.meta.Tuple(&.{T}),
//         };
//     }
//
//     fn normalizeChildren(children: anytype) NormalizedChildrenType(@TypeOf(children)) {
//         return switch (@typeInfo(@TypeOf(children))) {
//             @typeInfo(@TypeOf(null)) => .{},
//             .@"struct" => |info| if (info.is_tuple) children else .{children},
//             else => .{children},
//         };
//     }
//
//     fn callMethod(child_ptr: anytype, comptime method: []const u8, comptime optional: bool) !void {
//         const ptr_info = @typeInfo(@TypeOf(child_ptr));
//         comptime if (ptr_info != .pointer)
//             @compileError("View children must be addressable values.");
//
//         const ChildType = ptr_info.pointer.child;
//         switch (@typeInfo(ChildType)) {
//             .optional => {
//                 if (child_ptr.*) |*payload| {
//                     try callMethod(payload, method, optional);
//                 }
//                 return;
//             },
//             .@"struct" => |info| {
//                 if (info.is_tuple) {
//                     inline for (info.fields) |field| {
//                         const nested_ptr = &@field(child_ptr.*, field.name);
//                         try callMethod(nested_ptr, method, optional);
//                     }
//                     return;
//                 }
//             },
//             else => {},
//         }
//
//         if (!@hasDecl(ChildType, method)) {
//             if (optional) return;
//             @compileError(std.fmt.comptimePrint(
//                 "Child type '{s}' must implement method '{s}'",
//                 .{ @typeName(ChildType), method },
//             ));
//         }
//
//         const fn_ptr = @field(ChildType, method);
//         const fn_info = @typeInfo(@TypeOf(fn_ptr)).@"fn";
//
//         if (fn_info.return_type) |return_type| {
//             if (@typeInfo(return_type) == .error_union) {
//                 try @call(.auto, fn_ptr, .{child_ptr});
//             } else {
//                 _ = @call(.auto, fn_ptr, .{child_ptr});
//             }
//         } else {
//             _ = @call(.auto, fn_ptr, .{child_ptr});
//         }
//     }
//
//     fn callMethodVoid(child_ptr: anytype, comptime method: []const u8) void {
//         const ptr_info = @typeInfo(@TypeOf(child_ptr));
//         comptime if (ptr_info != .pointer)
//             @compileError("View children must be addressable values.");
//
//         const ChildType = ptr_info.pointer.child;
//         switch (@typeInfo(ChildType)) {
//             .optional => {
//                 if (child_ptr.*) |*payload| {
//                     callMethodVoid(payload, method);
//                 }
//                 return;
//             },
//             .Struct => |info| {
//                 if (info.is_tuple) {
//                     inline for (info.fields) |field| {
//                         const nested_ptr = &@field(child_ptr.*, field.name);
//                         callMethodVoid(nested_ptr, method);
//                     }
//                     return;
//                 }
//             },
//             else => {},
//         }
//
//         if (!@hasDecl(ChildType, method)) return;
//
//         const fn_ptr = @field(ChildType, method);
//         const fn_info = @typeInfo(@TypeOf(fn_ptr)).@"fn";
//
//         if (fn_info.return_type) |return_type| {
//             if (@typeInfo(return_type) == .error_union) {
//                 _ = @call(.auto, fn_ptr, .{child_ptr}) catch {};
//             } else {
//                 _ = @call(.auto, fn_ptr, .{child_ptr});
//             }
//         } else {
//             _ = @call(.auto, fn_ptr, .{child_ptr});
//         }
//     }
// };
