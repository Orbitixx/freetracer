const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const comp = @import("../components/Component.zig");
const Component = comp.Component;
const ComponentID = comp.ComponentID;
const ComponentRegistry = comp.ComponentRegistry;

pub const Event = enum {
    ISO_FILE_SELECTED,
    USB_DEVICES_DISCOVERED,
};

pub const AppObserver = struct {
    componentRegistry: *ComponentRegistry,

    pub fn onNotify(self: AppObserver, event: Event) void {
        switch (event) {
            Event.ISO_FILE_SELECTED => self.processISOFileSelected(),
            Event.USB_DEVICES_DISCOVERED => debug.print("\nReceived USB_DEVICES_DISCOVERED signal."),
        }
    }

    pub fn processISOFileSelected(self: AppObserver) void {
        self.componentRegistry.getComponent(ComponentID.USBDevicesList).?.USBDevicesList.*.componentActive = true;
    }
};
