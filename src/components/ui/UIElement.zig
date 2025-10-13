const std = @import("std");
const Debug = @import("freetracer-lib").Debug;

const Primitives = @import("./Primitives.zig");
const Rectangle = Primitives.Rectangle;
const Text = Primitives.Text;
const Texture = Primitives.Texture;
const Button = @import("./Button.zig");
const SpriteButton = @import("./SpriteButton.zig");

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

pub const View = struct {
    const vtable: UIElement.VTable = autoVTable(UIElement.VTable, View);

    element: UIElement = .{ .vtable = &vtable },
    frame: Bounds = undefined,
    background: ?Rectangle = null,
    children: ?[]UIElement = null,

    pub fn init(frame: Bounds, background: ?Rectangle, children: ?[]UIElement) View {
        // self.element.ptr = self;
        return .{
            .frame = frame,
            .background = background,
            .children = children,
        };
    }

    pub fn start(self: *View) !void {
        self.element.ptr = self;

        if (self.children) |children| {
            for (children) |*child| {
                try child.start();
            }
        }
    }

    pub fn update(self: *View) !void {
        if (self.children) |children| {
            for (children) |*child| {
                try child.update();
            }
        }
    }
    pub fn draw(self: *View) !void {
        if (self.background) |*bg| bg.draw();

        if (self.children) |children| {
            for (children) |*child| {
                try child.draw();
            }
        }
    }

    pub fn deinit(self: *View) void {
        if (self.children) |children| {
            for (children) |*child| {
                child.deinit();
            }
        }
    }
};
