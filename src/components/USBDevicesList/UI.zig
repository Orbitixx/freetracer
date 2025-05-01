const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const String = @import("../../lib/util/strings.zig");
const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const Checkbox = @import("../../lib/ui/Checkbox.zig").Checkbox();

const USBDevicesListComponent = @import("Component.zig");

pub const ComponentUI = struct {
    allocator: std.mem.Allocator,
    devices: std.ArrayList(UIDevice),

    pub fn init(self: *ComponentUI, ctx: *USBDevicesListComponent, devices: []MacOS.USBStorageDevice) void {
        for (devices, 0..devices.len) |device, i| {
            const buffer = self.allocator.allocSentinel(u8, 254, 0x00) catch |err| {
                std.debug.panic("\n{any}", .{err});
            };

            _ = std.fmt.bufPrintZ(
                buffer,
                "{s} - {s} ({d:.0}GB)",
                .{
                    device.deviceName,
                    String.truncToNull(device.bsdName),
                    @divTrunc(device.size, 1_000_000_000),
                },
            ) catch |err| {
                std.debug.panic("\n{any}", .{err});
            };

            debug.printf("\nComponentUI: formatted string is: {s}", .{buffer});

            var uiDevice: UIDevice = .{
                .name = String.truncToNull(device.deviceName),
                .bsdName = String.truncToNull(device.bsdName),
                .size = device.size,
                .fmtBuffer = buffer,
            };

            uiDevice.checkbox = Checkbox.init(uiDevice.fmtBuffer, 400, @as(f32, @floatFromInt(160 + 40 * i)), 20);
            uiDevice.checkbox.onSelected = USBDevicesListComponent.notifyCallback;
            uiDevice.checkbox.context = ctx;
            uiDevice.checkbox.data = String.truncToNull(device.bsdName);

            self.devices.append(uiDevice) catch |err| {
                debug.printf("\nWARNING: (USBDevicesListComponent) Unable to append UIDevice to ArrayList on first init. {any}", .{err});
            };
        }

        debug.printf("\nAppended {d} devices!", .{self.devices.items.len});
    }

    pub fn update(self: *ComponentUI) void {
        if (self.devices.items.len < 1) return;

        for (self.devices.items) |*device| {
            device.checkbox.update();
        }
    }

    pub fn draw(self: ComponentUI) void {
        if (self.devices.items.len < 1) return;

        for (self.devices.items) |*device| {
            device.checkbox.draw();
        }
    }

    pub fn deinit(self: ComponentUI) void {
        for (self.devices.items) |device| {
            self.allocator.free(device.fmtBuffer);
        }
        self.devices.deinit();
    }
};

pub const UIDevice = struct {
    name: []u8,
    bsdName: []u8,
    size: i64,
    fmtBuffer: [:0]u8,
    checkbox: Checkbox = undefined,
};
