const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const comp = @import("../components/Component.zig");
const Component = comp.Component;
const ComponentID = comp.ComponentID;
const ComponentRegistry = comp.ComponentRegistry;

pub const Event = enum {
    ISO_FILE_SELECTED,
};

pub const AppObserver = struct {
    componentRegistry: *ComponentRegistry,

    pub fn onNotify(self: AppObserver, event: Event) void {
        switch (event) {
            Event.ISO_FILE_SELECTED => processISOFileSelected(self),
        }
    }

    pub fn processISOFileSelected(self: AppObserver) void {
        self.componentRegistry.getComponent(ComponentID.USBDevicesList).?.USBDevicesList.*.componentActive = true;
    }
};
