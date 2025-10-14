const std = @import("std");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const ResourceManager = @import("../../managers/ResourceManager.zig").ResourceManagerSingleton;

const Primitives = @import("./Primitives.zig");
const Rectangle = Primitives.RectanglePro;
const TextDimensions = Primitives.TextDimensions;
const TextureResource = Primitives.TextureResource;
const Textbox = @import("./Textbox.zig");
// const Button = @import("./Button.zig");
const SpriteButton = @import("./SpriteButton.zig");
const Transform = @import("./Transform.zig");

const Style = @import("./Styles.zig");
const TextStyle = Style.TextStyle;

// const Layout = @import("./Layout.zig");
// const Bounds = Layout.Bounds;

// pub fn autoVTable(comptime VTableType: type, comptime ImplType: type) VTableType {
//     var vt: VTableType = undefined;
//
//     inline for (@typeInfo(VTableType).@"struct".fields) |field| {
//         // Each vtable field is a pointer-to-fn like *const fn(*anyopaque) <Ret>
//         const ptr_info = @typeInfo(field.type).pointer;
//         const fn_info = @typeInfo(ptr_info.child).@"fn";
//
//         // The concrete method on ImplType (e.g. update/draw/deinit)
//         const method = @field(ImplType, field.name);
//
//         // We generate a thunk with the *same* signature as the vtable field:
//         // fn(*anyopaque) ReturnType
//         const ReturnType = fn_info.return_type.?;
//
//         const Thunk = struct {
//             fn call(p: *anyopaque) ReturnType {
//                 const self: *ImplType = @ptrCast(@alignCast(p));
//                 // Call the concrete method; this compiles whether ReturnType is void or anyerror!void.
//                 return @call(.auto, method, .{self});
//             }
//         };
//
//         @field(vt, field.name) = &Thunk.call;
//     }
//     return vt;
// }

// pub const UIElement = struct {
//     ptr: *anyopaque = undefined,
//     vtable: *const VTable,
//
//     pub const VTable = struct {
//         start: *const fn (*anyopaque) anyerror!void,
//         update: *const fn (*anyopaque) anyerror!void,
//         draw: *const fn (*anyopaque) anyerror!void,
//         deinit: *const fn (*anyopaque) void,
//     };
//
//     pub fn start(self: *UIElement) !void {
//         return self.vtable.start(self.ptr);
//     }
//
//     pub fn update(self: *UIElement) !void {
//         return self.vtable.update(self.ptr);
//     }
//
//     pub fn draw(self: *UIElement) !void {
//         return self.vtable.draw(self.ptr);
//     }
//
//     pub fn deinit(self: *UIElement) void {
//         return self.vtable.deinit(self.ptr);
//     }
// };

pub const UIElement = union(enum) {
    View: View,
    Text: Text,
    Textbox: Textbox,
    Texture: Texture,
    // Button: Button,
    // SpriteButton: SpriteButton,

    pub fn start(self: *UIElement) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).start(),
        }
    }

    pub fn update(self: *UIElement) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).update(),
        }
    }

    pub fn draw(self: *UIElement) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).draw(),
        }
    }

    pub fn deinit(self: *UIElement) void {
        switch (self.*) {
            inline else => |*element| @constCast(element).deinit(),
        }
    }

    pub fn onEvent(self: *UIElement, event: UIEvent) void {
        switch (self.*) {
            inline else => |*element| @constCast(element).onEvent(event),
        }
    }
};

pub const UIElementIdentifier = enum(u8) {
    ImageInfoBoxText,
};

pub const UIEventType = enum(u8) {
    TextChangedEvent,
};

pub const UIEvent = union(enum) {
    TextChanged: struct { target: UIElementIdentifier, text: [:0]const u8 },
};

pub const View = struct {
    identifier: ?UIElementIdentifier = null,
    allocator: Allocator,
    transform: Transform = .{},
    background: ?Rectangle = null,
    children: ArrayList(UIElement),

    pub fn init(allocator: Allocator, identifier: ?UIElementIdentifier, transform: Transform, background: ?Rectangle) View {
        return .{
            .identifier = identifier,
            .allocator = allocator,
            .transform = transform,
            .background = background,
            .children = ArrayList(UIElement).empty,
        };
    }

    pub fn addChild(self: *View, child: UIElement, relativeTransform: ?*Transform) !void {
        var mutableChild = child;

        switch (mutableChild) {
            inline else => |*el| {
                if (relativeTransform) |rt| el.transform.relativeRef = rt else el.transform.relativeRef = &self.transform;
            },
        }

        try self.children.append(self.allocator, mutableChild);
    }

    pub fn start(self: *View) !void {
        Debug.log(.DEBUG, "View start() called.", .{});

        self.layoutSelf();

        for (self.children.items) |*child| {
            try child.start();
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

    pub fn onEvent(self: *View, event: UIEvent) void {
        _ = self;
        _ = event;
        Debug.log(.DEBUG, "View recevied a UIEvent.", .{});
    }

    pub fn emitEvent(self: *View, event: UIEvent) void {
        for (self.children.items) |*child| {
            child.onEvent(event);
        }
    }

    fn layoutSelf(self: *View) void {
        _ = self.transform.resolve();

        if (self.background) |*bg| {
            bg.transform = self.transform;
        }
    }
};

pub const Text = struct {
    identifier: ?UIElementIdentifier = null,
    transform: Transform = .{},
    textBuffer: [256]u8,
    style: TextStyle,
    font: rl.Font,
    background: ?Rectangle = null,

    pub fn init(identifier: ?UIElementIdentifier, value: [:0]const u8, transform: Transform, style: TextStyle) Text {

        // TODO: Extract magic number to a constant
        if (value.len > 256) Debug.log(.WARNING, "Text UIElement's value length exceeded allowed max: {s}", .{value});

        var textValue: [256]u8 = std.mem.zeroes([256]u8);
        @memcpy(textValue[0..if (value.len > 256) 255 else value.len], if (value.len > 256) value[0..255] else value);

        return .{
            .identifier = identifier,
            .transform = transform,
            .textBuffer = textValue,
            .style = style,
            .font = ResourceManager.getFont(style.font),
        };
    }

    pub fn start(self: *Text) !void {
        self.transform.resolve();
        const textDims: rl.Vector2 = rl.measureTextEx(self.font, @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00)), self.style.fontSize, self.style.spacing);
        self.transform.size = .pixels(textDims.x, textDims.y);
    }

    pub fn update(self: *Text) !void {
        self.transform.resolve();
    }

    pub fn draw(self: *Text) !void {
        rl.drawTextEx(
            self.font,
            @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00)),
            self.transform.positionAsVector2(),
            self.style.fontSize,
            self.style.spacing,
            self.style.textColor,
        );
    }

    pub fn onEvent(self: *Text, event: UIEvent) void {
        Debug.log(.DEBUG, "Text recevied a UIEvent: {any}", .{event});

        switch (event) {
            inline else => |e| if (e.target != self.identifier) return,
        }

        switch (event) {
            .TextChanged => |e| {
                self.setValue(e.text);
            },
        }
    }

    pub fn deinit(self: *Text) void {
        _ = self;
    }

    pub fn setValue(self: *Text, newValue: [:0]const u8) void {
        self.textBuffer = std.mem.zeroes([256]u8);
        @memcpy(self.textBuffer[0..if (newValue.len > 256) 256 else newValue.len], if (newValue.len > 256) newValue[0..256] else newValue);
    }

    pub fn getDimensions(self: Text) TextDimensions {
        const dims = rl.measureTextEx(self.font, self.value, self.style.fontSize, self.style.spacing);
        return .{ .width = dims.x, .height = dims.y };
    }
};

pub const Texture = struct {
    identifier: ?UIElementIdentifier = null,
    transform: Transform,
    resource: TextureResource,
    texture: rl.Texture2D,
    tint: rl.Color = Style.Color.white,
    background: ?Rectangle = null,

    pub fn init(identifier: ?UIElementIdentifier, resource: TextureResource, transform: Transform, tint: ?rl.Color) Texture {
        const texture: rl.Texture2D = ResourceManager.getTexture(resource);

        return .{
            .identifier = identifier,
            .transform = transform,
            .resource = resource,
            .texture = texture,
            .tint = if (tint) |t| t else Style.Color.white,
        };
    }

    pub fn start(self: *Texture) !void {
        const tWidth: f32 = @floatFromInt(self.texture.width);
        const tHeight: f32 = @floatFromInt(self.texture.height);
        self.transform.size = .pixels(tWidth, tHeight);
        self.transform.resolve();
    }

    pub fn update(self: *Texture) !void {
        self.transform.resolve();
    }

    pub fn draw(self: *Texture) !void {
        rl.drawTextureEx(
            self.texture,
            .{ .x = self.transform.x, .y = self.transform.y },
            self.transform.rotation,
            self.transform.scale,
            self.tint,
        );
    }

    pub fn onEvent(self: *Texture, event: UIEvent) void {
        _ = self;
        _ = event;
        Debug.log(.DEBUG, "Texture recevied a UIEvent.", .{});
    }

    /// API-Compliance function. Texture unloading occurs in ResourceManager.
    pub fn deinit(self: *Texture) void {
        _ = self;
    }
};
