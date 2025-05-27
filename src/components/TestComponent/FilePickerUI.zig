const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const ISOFilePicker = @import("./TestComponent.zig").ISOFilePickerComponent;

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;

pub const ISOFilePickerUIState = struct {};
pub const ComponentState = ComponentFramework.ComponentState(ISOFilePickerUIState);

const ISOFilePickerUI = @This();

component: ?Component = null,
state: ComponentState,

// pub fn init(parent: *ISOFilePicker) ISOFilePickerUI {
//     var comp = ISOFilePickerUI{
//         .state = .{},
//     };
//
//     return comp;
// }
