const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const rl = @import("raylib");

const ComponentFramework = @import("../framework/import/index.zig");

const ISOFilePickerUIState = struct {};

const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(ISOFilePickerUIState);
const ComponentWorker = ComponentFramework.Worker(ISOFilePickerUIState);

const Button = @This();

const BUTTON_PADDING: f32 = 16;

pub const ButtonState = enum {
    NORMAL,
    HOVER,
    ACTIVE,
};

pub const ButtonColorVariant = struct {
    rect: rl.Color,
    text: rl.Color,
};

pub const ButtonColorVariants = struct {
    normal: ButtonColorVariant,
    hover: ButtonColorVariant,
    active: ButtonColorVariant,
};
