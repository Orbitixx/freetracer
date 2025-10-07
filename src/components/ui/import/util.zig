const Debug = @import("freetracer-lib").Debug;
const EventManager = @import("../../../managers/EventManager.zig").EventManagerSingleton;
const ISOFilePickerUI = @import("../../FilePicker/FilePickerUI.zig");
const DeviceListUI = @import("../../DeviceList/DeviceListUI.zig");
const Transform = @import("../Primitives.zig").Transform;

pub fn queryComponentTransform(component: type) Transform {
    var bgRectTransform: Transform = Transform{ .x = 0, .y = 0, .w = 0, .h = 0 };

    const eventType: type = switch (component) {
        ISOFilePickerUI => ISOFilePickerUI.Events.onUIDimensionsQueried,
        DeviceListUI => DeviceListUI.Events.onUITransformQueried,
        else => {
            Debug.log(.WARNING, "queryComponentTransform(): Unknown component provided as argument. Returning 0-based Transform.", .{});
            return bgRectTransform;
        },
    };

    const event = eventType.create(null, &.{ .result = &bgRectTransform });

    const dataResult = EventManager.signal(component.ComponentName, event) catch |err| {
        Debug.log(.ERROR, "queryComponentTransform(): unable to signal {s}, error: {any}", .{ component.ComponentName, err });
        return bgRectTransform;
    };

    if (!dataResult.success) Debug.log(.WARNING, "queryComponentTransform(): unable to query {s}'s bgRect dimensions.", .{component.ComponentName});

    return bgRectTransform;
}
