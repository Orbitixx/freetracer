const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const String = @import("../../lib/util/strings.zig");
const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const rl = @import("raylib");
const UI = @import("../../lib/ui/ui.zig");
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const ResourceManager = @import("../../managers/ResourceManager.zig").ResourceManagerSingleton;

const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const AppObserverEvent = @import("../../observers/AppObserver.zig").Event;

const SiblingComponentUI = @import("../FilePicker/FilePickerUI.zig");

const relW = WindowManager.relW;
const relH = WindowManager.relH;

const Font = @import("../../managers/ResourceManager.zig").FONT;
const Texture = @import("../../managers/ResourceManager.zig").TEXTURE;

const ComponentID = @import("../Registry.zig").ComponentID;

const Checkbox = @import("../../lib/ui/Checkbox.zig").Checkbox();

const FilePickerComponent = @import("../FilePicker/FilePicker.zig");
const USBDevicesListComponent = @import("./Component.zig");

const Self = @This();

active: bool = false,
allocator: std.mem.Allocator,
devices: std.ArrayList(UIDevice),
appObserver: *const AppObserver,
prevSiblingUI: ?*SiblingComponentUI = null,
bgRect: ?UI.Rectangle = null,
confirmButton: ?UI.Button() = null,

pub fn init(self: *Self) void {
    self.prevSiblingUI = &self.appObserver.getComponent(FilePickerComponent, ComponentID.ISOFilePicker).ui;

    self.recalculateUi();
}

pub fn recalculateUi(self: *Self) void {
    const xOffset: f32 = self.prevSiblingUI.?.bgRect.?.x + self.prevSiblingUI.?.bgRect.?.w;
    self.bgRect = UI.Rectangle{ .x = xOffset + relW(0.02), .y = relH(0.2), .w = relW(0.35), .h = relH(0.7) };

    self.confirmButton = UI.Button().init("CONFIRM", 0, 0, 14, SiblingComponentUI.BUTTON_COLOR_VARIANTS);

    const btnX: f32 = self.bgRect.?.relW(0.5) - @divTrunc(self.confirmButton.?.rect.transform.w, 2);
    const btnY: f32 = self.bgRect.?.relH(0.9) - @divTrunc(self.confirmButton.?.rect.transform.h, 2);

    self.confirmButton.?.setPosition(btnX, btnY);
}

pub fn update(self: *Self) void {
    // if (self.active) self.recalculateUi();
    if (self.devices.items.len < 1) return;

    for (self.devices.items) |*device| {
        device.checkbox.update();
    }

    if (self.confirmButton) |*button| button.events();
}

fn drawActive(self: *Self) void {
    // TODO: Does not need to be recalculated every frame
    // const xOffset: f32 = self.prevSiblingUI.?.bgRect.?.x + self.prevSiblingUI.?.bgRect.?.w;
    self.bgRect.?.w = relW(0.35);

    rl.drawRectangleRounded(self.bgRect.?.toRaylibRectangle(), 0.04, 0, .{ .r = 49, .g = 85, .b = 100, .a = 255 });
    rl.drawRectangleRoundedLinesEx(self.bgRect.?.toRaylibRectangle(), 0.04, 0, 2, .white);

    rl.drawTextEx(
        ResourceManager.getFont(Font.JERSEY10_REGULAR),
        "device",
        .{ .x = self.bgRect.?.x + 12, .y = self.bgRect.?.relH(0.01) },
        34,
        0,
        .white,
    );

    if (self.devices.items.len < 1) return;

    for (self.devices.items) |*device| {
        device.checkbox.draw();
    }

    if (self.confirmButton) |button| {
        button.draw();
    }

    // rl.drawTextureEx(ResourceManager.getTexture(Texture.DISK_IMAGE), .{ .x = self.bgRect.?.relW(0.25), .y = self.bgRect.?.relH(0.3) }, 0, 1.0, .white);

}

fn drawInactive(self: *Self) void {
    // TODO: Does not need to be recalculated every frame
    // const xOffset: f32 = self.prevSiblingUI.?.bgRect.?.x + self.prevSiblingUI.?.bgRect.?.w;
    self.bgRect.?.w = relW(0.16);

    rl.drawRectangleRounded(self.bgRect.?.toRaylibRectangle(), 0.04, 0, rl.Color.init(49, 65, 84, 255));
    rl.drawRectangleRoundedLinesEx(self.bgRect.?.toRaylibRectangle(), 0.04, 0, 2, rl.Color.init(49, 85, 100, 255));

    // const comp: *USBDevicesListComponent = self.appObserver.getComponent(USBDevicesListComponent, ComponentID.USBDevicesList);

    rl.drawTextEx(
        ResourceManager.getFont(Font.JERSEY10_REGULAR),
        "device",
        .{ .x = self.bgRect.?.x + 12, .y = self.bgRect.?.relH(0.01) },
        34,
        0,
        rl.Color.init(174, 216, 255, 255),
    );

    // const textWidth: f32 = rl.measureTextEx(ResourceManager.getFont(Font.ROBOTO_REGULAR), self.fileName.?, 14, 0).x;
    // const textWidthCorrection: f32 = textWidth / 2.0;
    //
    // rl.drawTextEx(
    //     ResourceManager.getFont(Font.ROBOTO_REGULAR),
    //     self.fileName.?,
    //     .{ .x = self.bgRect.?.relW(0.5) - textWidthCorrection, .y = self.bgRect.?.relH(0.7) },
    //     14,
    //     0,
    //     .white,
    // );
    //
    // const diskTexture = ResourceManager.getTexture(Texture.DISK_IMAGE);
    // const textureScale: f32 = 0.6;
    // const textureWidth: f32 = @floatFromInt(diskTexture.width);
    // const textureHeight: f32 = @floatFromInt(diskTexture.height);
    //
    // const widthCorrection: f32 = @divTrunc(textureWidth * textureScale, 2);
    // const heightCorrection: f32 = @divTrunc(textureHeight * textureScale, 2);
    //
    // rl.drawTextureEx(
    //     diskTexture,
    //     .{ .x = bgRect.relW(0.5) - widthCorrection, .y = bgRect.relH(0.5) - heightCorrection },
    //     0,
    //     textureScale,
    //     rl.Color.init(255, 255, 255, 80),
    // );
}

pub fn draw(self: *Self) void {
    if (self.active) self.drawActive() else self.drawInactive();
}

// pub fn draw(self: ComponentUI) void {
// if (self.devices.items.len < 1) return;
//
// for (self.devices.items) |*device| {
//     device.checkbox.draw();
// }
// }

pub fn setDevices(self: *Self, ctx: *USBDevicesListComponent, devices: []MacOS.USBStorageDevice) void {
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

        uiDevice.checkbox = Checkbox.init(uiDevice.fmtBuffer, self.bgRect.?.x + 12, self.bgRect.?.relH(0.12) + 30 * @as(f32, @floatFromInt(i)), 20);
        uiDevice.checkbox.onSelected = USBDevicesListComponent.notifyCallback;
        uiDevice.checkbox.context = ctx;
        uiDevice.checkbox.data = String.truncToNull(device.bsdName);

        self.devices.append(uiDevice) catch |err| {
            debug.printf("\nWARNING: (USBDevicesListComponent/UI) Unable to append UIDevice to ArrayList on first init. {any}", .{err});
        };
    }
}

pub fn deinit(self: Self) void {
    for (self.devices.items) |device| {
        self.allocator.free(device.fmtBuffer);
    }
    self.devices.deinit();
}

pub const UIDevice = struct {
    name: []u8,
    bsdName: []u8,
    size: i64,
    fmtBuffer: [:0]u8,
    checkbox: Checkbox = undefined,
};
