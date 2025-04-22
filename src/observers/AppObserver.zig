const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const comp = @import("../components/Component.zig");
const Component = @import("../components/Component.zig");
const ComponentID = @import("../components/Registry.zig").ComponentID;
const ComponentRegistry = @import("../components/Registry.zig").ComponentRegistry;

pub const Event = enum {
    ISO_FILE_SELECTED,
    USB_DEVICES_DISCOVERED,
    USB_DEVICE_SELECTED,
};

pub const Payload = struct {
    data: ?[]u8 = null,
};

pub const AppObserver = struct {
    componentRegistry: *ComponentRegistry,

    pub fn onNotify(self: AppObserver, event: Event, payload: Payload) void {
        switch (event) {
            .ISO_FILE_SELECTED => self.processISOFileSelected(),
            .USB_DEVICES_DISCOVERED => debug.print("\nAppObserver: USB_DEVICES_DISCOVERED signal received."),
            .USB_DEVICE_SELECTED => debug.printf("\nAppObserver: USB_DEVICE_SELECTED signal received, data: {any}", .{payload.data}),
        }
    }

    pub fn processISOFileSelected(self: AppObserver) void {
        self.componentRegistry.getComponent(ComponentID.USBDevicesList).?.enable();
    }
};
