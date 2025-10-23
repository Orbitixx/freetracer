const rl = @import("raylib");
const UIFramework = @import("./import.zig");
const Text = UIFramework.Text;

pub const UIElementIdentifier = enum(u8) {
    FilePickerHeaderDivider,
    FilePickerFileDropzone,
    FilePickerImageInfoTextbox,
    FilePickerImageSizeText,
    FilePickerConfirmButton,
    FilePickerImageSelectedTexture,
    FilePickerImageSelectedTextbox,
    FilePickerImageSelectedGlowTexture,

    DeviceListConfirmButton,
    DeviceListDeviceListBox,
    DeviceListNoDevicesText,
    DeviceListRefreshDevicesButton,
    DeviceListPlaceholderTexture,
    DeviceListDeviceSelectedTexture,
    DeviceListDeviceSelectedGlowTexture,
    DeviceListHeaderDivider,

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

    DataFlasherLaunchButton,

    GenericProgressBox,
};

// pub const UIEventType = enum(u8) {
//     TextChangedEvent,
//     StateChangedEvent,
// };

pub const UIEvent = union(enum) {
    TextChanged: struct { target: UIElementIdentifier, text: ?[:0]const u8 = null, style: ?Text.TextStyle = null, pulsate: ?Text.PulsateState = null },
    StateChanged: struct { target: ?UIElementIdentifier = null, isActive: bool },
    SpriteButtonEnabledChanged: struct { target: UIElementIdentifier, enabled: bool },
    ProgressValueChanged: struct { target: UIElementIdentifier, percent: u64 },
    SizeChanged: struct { target: UIElementIdentifier, size: UIFramework.SizeSpec },
    BorderColorChanged: struct { target: UIElementIdentifier, color: rl.Color },
    ColorChanged: struct { target: UIElementIdentifier, color: rl.Color },
};
