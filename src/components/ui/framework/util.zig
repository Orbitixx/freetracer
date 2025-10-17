const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

const EventManager = @import("../../../managers/EventManager.zig").EventManagerSingleton;

const UIFramework = @import("./import.zig");
const RelativeRef = UIFramework.RelativeRef;
const View = UIFramework.View;
const UIElement = UIFramework.UIElement;
const Transform = UIFramework.Transform;

const FilePickerUI = @import("../../FilePicker/FilePickerUI.zig");
const DeviceListUI = @import("../../DeviceList/DeviceListUI.zig");

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

pub fn queryViewTransform(component: type) !*Transform {
    var viewTransform: *Transform = undefined;

    const eventType: type = switch (component) {
        FilePickerUI => FilePickerUI.Events.onRootViewTransformQueried,
        DeviceListUI => DeviceListUI.Events.onRootViewTransformQueried,
        else => {
            Debug.log(.ERROR, "queryViewTransform(): Unknown component provided as argument: {any}", .{component});
            return error.UnknownComponentType;
        },
    };

    const event = eventType.create(null, &.{ .result = &viewTransform });
    const dataResult = try EventManager.signal(component.ComponentName, event);
    if (!dataResult.success) Debug.log(.WARNING, "queryComponentTransform(): unable to query {s}'s layout transform.", .{component.ComponentName});

    return viewTransform;
}
