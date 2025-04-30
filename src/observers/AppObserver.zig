const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const MacOS = @import("../modules/macos/MacOSTypes.zig");
const DiskArbitration = @import("../modules/macos/DiskArbitration.zig");
const PrivilegedHelper = @import("../modules/macos/PrivilegedHelper.zig");

const USBDevicesListComponent = @import("../components/USBDevicesList/Component.zig");

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
            .USB_DEVICE_SELECTED => {
                debug.printf("\nAppObserver: USB_DEVICE_SELECTED signal received, data: {s}", .{payload.data.?});
                if (payload.data) |data| self.processUSBDeviceSelected(data) else debug.print("\nAppObserver: NULL payload data received.");
            },
        }
    }

    pub fn processISOFileSelected(self: AppObserver) void {
        self.componentRegistry.getComponent(ComponentID.USBDevicesList).?.enable();
    }

    pub fn processUSBDeviceSelected(self: AppObserver, bsdName: []u8) void {
        const usbComp: *USBDevicesListComponent = @ptrCast(@alignCast(self.componentRegistry.getComponent(ComponentID.USBDevicesList).?.ptr));
        const maybe_device: ?MacOS.USBStorageDevice = usbComp.macos_getDevice(bsdName);

        if (maybe_device == null) {
            debug.print("\nWARNING: macos_getDevice() returned NULL. Aborting DiskArbitration operation...");
            return;
        }

        const device = maybe_device.?;

        debug.printf("\nAppObserver, processUSBDeviceSelected(): device name: {s}, service id: {d}", .{ device.deviceName, device.serviceId });

        for (device.volumes.items) |volume| {
            const response = PrivilegedHelper.performPrivilegedTask(volume.bsdName);
            debug.printf("\nAppObserver unmount request for {s} received response: {any}", .{ volume.bsdName, response });
        }

        // DiskArbitration.unmountAllVolumes(&device) catch |err| {
        //     debug.printf("\nERROR: Failed to unmount volumes on {s}. Error message: {any}", .{ device.bsdName, err });
        // };
    }
};
