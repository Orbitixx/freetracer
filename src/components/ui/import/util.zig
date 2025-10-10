const Debug = @import("freetracer-lib").Debug;
const EventManager = @import("../../../managers/EventManager.zig").EventManagerSingleton;
const FilePickerUI = @import("../../FilePicker/FilePickerUI.zig");
const DeviceListUI = @import("../../DeviceList/DeviceListUI.zig");
const Transform = @import("../Primitives.zig").Transform;

pub fn queryComponentTransform(component: type) !*Transform {
    var bgRectTransform: *Transform = undefined;

    const eventType: type = switch (component) {
        FilePickerUI => FilePickerUI.Events.onUIDimensionsQueried,
        DeviceListUI => DeviceListUI.Events.onUITransformQueried,
        else => {
            Debug.log(.WARNING, "queryComponentTransform(): Unknown component provided as argument. Returning 0-based Transform.", .{});
            return bgRectTransform;
        },
    };

    const event = eventType.create(null, &.{ .result = &bgRectTransform });
    const dataResult = try EventManager.signal(component.ComponentName, event);
    if (!dataResult.success) Debug.log(.WARNING, "queryComponentTransform(): unable to query {s}'s bgRect dimensions.", .{component.ComponentName});

    return bgRectTransform;
}
