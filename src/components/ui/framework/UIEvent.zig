pub const UIElementIdentifier = enum(u8) {
    ImageInfoBoxText,
};

pub const UIEventType = enum(u8) {
    TextChangedEvent,
};

pub const UIEvent = union(enum) {
    TextChanged: struct { target: UIElementIdentifier, text: [:0]const u8 },
};
