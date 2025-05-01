const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const UI = @import("../../lib/ui/ui.zig");

const FilePickerComponent = @import("Component.zig");
const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const AppObserverEvent = @import("../../observers/AppObserver.zig").Event;

const Self = @This();

/// ComponentUI's focused state relative to other components
active: bool = false,
appObserver: *const AppObserver,
button: ?UI.Button() = null,

pub fn init(self: *Self) void {
    self.button = UI.Button().init("Select ISO...", 150, 150, 18, .white, .red);
}

pub fn update(self: *Self) void {
    var isBtnClicked = false;

    if (self.button != null) {
        self.button.?.events();
        isBtnClicked = self.button.?.mouseClick;
    }

    if (isBtnClicked) self.appObserver.onNotify(AppObserverEvent.SELECT_ISO_BTN_CLICKED, .{});
}

pub fn draw(self: Self) void {
    if (self.button != null) self.button.?.draw();
}
