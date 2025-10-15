const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

const UIFramework = @import("./import.zig");
const RelativeRef = UIFramework.RelativeRef;
const View = UIFramework.View;
const UIElement = UIFramework.UIElement;
const Transform = UIFramework.Transform;

pub fn resolveRelative(ctx: *const anyopaque, ref: RelativeRef) rl.Rectangle {
    const self: *const View = @ptrCast(@alignCast(ctx));
    switch (ref) {
        .Parent => return self.transform.asRaylibRectangle(),
        .NodeId => |id| {
            if (self.idMap.get(id)) |idx| {
                const child: *const UIElement = &self.children.items[idx];
                // Get that child's transform (without recursing resolve)
                return getTransformOf(child).asRaylibRectangle();
            } else {
                // Fallback: reference missing -> parent rect
                Debug.log(.WARNING, "RelativeRef NodeId not found: {s}", .{id});
                return self.transform.asRaylibRectangle();
            }
        },
    }
}

/// Extract a *const Transform from any UIElement (no recursion).
pub fn getTransformOf(el: *const UIElement) *const Transform {
    return switch (el.*) {
        // .View => |*v| &v.transform,
        // .Text => |*t| &t.transform,
        // .Textbox => |*tb| &tb.transform,
        // .Texture => |*tex| &tex.transform,
        // .FileDropzone => |*fdz| &fdz.transform,
        // inline else => unreachable,
        inline else => |*concrete| &concrete.transform,
    };
}
