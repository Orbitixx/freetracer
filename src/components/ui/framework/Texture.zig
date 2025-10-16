const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

const ResourceImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceImport.ResourceManagerSingleton;
const TextureResource = ResourceImport.TextureResource;

const WindowManager = @import("../../../managers/WindowManager.zig").WindowManagerSingleton;

const Transform = @import("./Transform.zig");
const Rectangle = @import("./Rectangle.zig");

const Event = @import("./UIEvent.zig");
const UIEvent = Event.UIEvent;
const UIElementIdentifier = Event.UIElementIdentifier;

const Styles = @import("../Styles.zig");
const TextStyle = Styles.TextStyle;
const Color = Styles.Color;

const Texture = @This();

identifier: ?UIElementIdentifier = null,
transform: Transform,
resource: TextureResource,
texture: rl.Texture2D,
tint: rl.Color = Color.white,
background: ?Rectangle = null,

shader: rl.Shader,
res: rl.Vector2 = .{ .x = 0, .y = 0 },
px: rl.Vector2 = .{ .x = 0, .y = 0 },

pub fn init(identifier: ?UIElementIdentifier, resource: TextureResource, transform: Transform, tint: ?rl.Color) Texture {
    const texture: rl.Texture2D = ResourceManager.getTexture(resource);

    return .{
        .identifier = identifier,
        .transform = transform,
        .resource = resource,
        .texture = texture,
        .tint = if (tint) |t| t else Color.white,
        .shader = ResourceManager.getShader(.PIXELATE) catch unreachable,
    };
}

pub fn start(self: *Texture) !void {
    const tWidth: f32 = @floatFromInt(self.texture.width);
    const tHeight: f32 = @floatFromInt(self.texture.height);
    self.transform.size = .pixels(tWidth, tHeight);
    self.transform.resolve();

    const res = rl.getShaderLocation(self.shader, "resolution");
    const px = rl.getShaderLocation(self.shader, "pixelSize");

    self.res = .{ .x = WindowManager.getWindowWidth(), .y = WindowManager.getWindowHeight() };
    rl.setShaderValue(self.shader, res, &self.res, .vec2);

    self.px = .{ .x = 30, .y = 30 };
    rl.setShaderValue(self.shader, px, &self.px, .vec2);
}

pub fn update(self: *Texture) !void {
    self.transform.resolve();
}

pub fn draw(self: *Texture) !void {
    rl.beginShaderMode(self.shader);
    rl.drawTextureEx(
        self.texture,
        .{ .x = self.transform.x, .y = self.transform.y },
        self.transform.rotation,
        self.transform.scale,
        self.tint,
    );
    rl.endShaderMode();
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
