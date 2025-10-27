const std = @import("std");
const rl = @import("raylib");
const UIFramework = @import("./import.zig");
const Text = UIFramework.Text;

pub const MAX_VIEW_EVENT_EXEMPT_CHILDREN = 10;

pub const UIElementIdentifier = enum(u8) {
    ZeroElement = 0,

    AppManagerSatteliteGraphic,
    AppManagerResetAppButton,

    FilePickerHeaderDivider,
    FilePickerFileDropzone,
    FilePickerImageInfoTextbox,
    FilePickerImageSizeText,
    FilePickerConfirmButton,
    FilePickerImageSelectedTexture,
    FilePickerImageSelectedTextbox,
    FilePickerImageSelectedGlowTexture,
    FilePickerImageSelectedBarRect,
    FilePickerImageSelectedBarText,

    DeviceListConfirmButton,
    DeviceListDeviceListBox,
    DeviceListNoDevicesText,
    DeviceListRefreshDevicesButton,
    DeviceListPlaceholderTexture,
    DeviceListDeviceSelectedTexture,
    DeviceListDeviceSelectedGlowTexture,
    DeviceListHeaderDivider,
    DeviceListDeviceSelectedBarRect,
    DeviceListDeviceSelectedBarText,
    DeviceListDeviceSelectedText,

    DataFlasherHeaderDivider,
    DataFlasherStatusBgRect,
    DataFlasherPlaceholderTexture,
    DataFlasherStatusBoxCoverRect,
    DataFlasherStatusBoxCoverText,
    DataFlasherStatusBoxCoverTexture,
    DataFlasherStatusHeaderText,
    DataFlasherStatusBoxProgressPercentTextFront,
    DataFlasherStatusBoxProgressPercentTextBack,
    DataFlasherStatusBoxProgressBox,
    DataFlasherStatusBoxProgressText,
    DataFlasherStatusBoxSpeedText,
    DataFlasherStatusBoxETAText,
    DataFlasherLogsBgRect,
    DataFlasherLogsTextbox,
    DataFlasherCopyLogsButton,

    DataFlasherLaunchButton,

    GenericProgressBox,
};

pub fn exceptChildren(children: anytype) [MAX_VIEW_EVENT_EXEMPT_CHILDREN]UIElementIdentifier {

    // TODO: perform comptime type checking

    var result = std.mem.zeroes([MAX_VIEW_EVENT_EXEMPT_CHILDREN]UIElementIdentifier);
    inline for (children, 0..) |child, i| result[i] = child;
    return result;
}

pub fn invertChildren(children: anytype) [MAX_VIEW_EVENT_EXEMPT_CHILDREN]UIElementIdentifier {

    // TODO: perform comptime type checking

    var result = std.mem.zeroes([MAX_VIEW_EVENT_EXEMPT_CHILDREN]UIElementIdentifier);
    inline for (children, 0..) |child, i| result[i] = child;
    return result;
}

pub const UIEvent = union(enum) {
    TextChanged: struct {
        target: UIElementIdentifier,
        text: ?[:0]const u8 = null,
        style: ?Text.TextStyle = null,
        pulsate: ?Text.PulsateState = null,
    },

    StateChanged: struct {
        isActive: bool,
        // Null means to target all children UIElements
        target: ?UIElementIdentifier = null,
        except: ?[MAX_VIEW_EVENT_EXEMPT_CHILDREN]UIElementIdentifier = null,
        invert: ?[MAX_VIEW_EVENT_EXEMPT_CHILDREN]UIElementIdentifier = null,
    },

    SpriteButtonEnabledChanged: struct { target: UIElementIdentifier, enabled: bool },
    ProgressValueChanged: struct { target: UIElementIdentifier, percent: u64 },
    SizeChanged: struct { target: UIElementIdentifier, size: UIFramework.SizeSpec },
    PositionChanged: struct { target: UIElementIdentifier, position: UIFramework.PositionSpec },
    BorderColorChanged: struct { target: UIElementIdentifier, color: rl.Color },
    ColorChanged: struct { target: UIElementIdentifier, color: rl.Color },
    CopyTextToClipboard: struct { target: UIElementIdentifier },
};
