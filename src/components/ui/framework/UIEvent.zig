const UIFramework = @import("./import.zig");

pub const UIElementIdentifier = enum(u8) {
    FilePickerFileDropzone,
    FilePickerImageInfoTextbox,
    FilePickerImageSizeText,
    FilePickerConfirmButton,
    FilePickerImageSelectedTexture,
    FilePickerImageSelectedTextbox,
};

// pub const UIEventType = enum(u8) {
//     TextChangedEvent,
//     StateChangedEvent,
// };

pub const UIEvent = union(enum) {
    TextChanged: struct { target: UIElementIdentifier, text: [:0]const u8 },
    StateChanged: struct { target: ?UIElementIdentifier = null, isActive: bool },
    SpriteButtonEnabledChanged: struct {
        target: UIElementIdentifier,
        enabled: bool,
    },
};
