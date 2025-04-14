const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
const rg = @import("raygui");
const osd = @import("osdialog");

const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");
const MacOS = @import("modules/macos/MacOSTypes.zig");
const IOKit = @import("modules/macos/IOKit.zig");
const DiskArbitration = @import("modules/macos/DiskArbitration.zig");

const UI = @import("lib/ui/ui.zig");
const Checkbox = @import("lib/ui/Checkbox.zig").Checkbox();

const AppController = @import("AppController.zig");
const Component = @import("components/Component.zig").Blueprint;

const FilePicker = @import("components/FilePicker/Index.zig");
const USBDevicesList = @import("components/USBDevicesList/Index.zig");

// const ArgValidator = struct {
//     isoPath: bool = false,
//     devicePath: bool = false,
// };

const WINDOW_WIDTH = 850;
const WINDOW_HEIGHT = 500;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "");
    defer rl.closeWindow(); // Close window and OpenGL context

    // LOAD FONTS HERE

    rl.setTargetFPS(60);

    //--------------------------------------------------------------------------------------
    //

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    var isoFilePickerState: FilePicker.State = .{ .allocator = allocator };

    var usbDevicesListState: USBDevicesList.State = .{
        .allocator = allocator,
        .devices = std.ArrayList(MacOS.USBStorageDevice).init(allocator),
    };

    var appController: AppController = .{};

    //--- @COMPONENTS ----------------------------------------------------------------------

    var componentRegistry: ComponentRegistry = .{
        .allocator = allocator,
        .components = std.ArrayList(*Component).init(allocator),
    };
    defer componentRegistry.deinit();

    var filePickerComponent: FilePicker.Component = .{
        .allocator = allocator,
        .state = &isoFilePickerState,
        .button = UI.Button().init("Select ISO...", relW(0.19), relH(0.80), 14, .white, .red),
    };

    const pISOFilePickerComponent = componentRegistry.registerComponent(
        allocator,
        &appController,
        .{ .FilePicker = &filePickerComponent },
    );

    appController.isoFilePicker = pISOFilePickerComponent.FilePicker;

    var usbDevicesListComponent: USBDevicesList.Component = .{
        .allocator = allocator,
        .state = &usbDevicesListState,
    };

    const pUSBDevicesListComponent = componentRegistry.registerComponent(
        allocator,
        &appController,
        .{ .USBDevicesList = &usbDevicesListComponent },
    );

    appController.usbDevicesList = pUSBDevicesListComponent.USBDevicesList;

    //--- @ENDCOMPONENTS -------------------------------------------------------------------

    const isoRect: UI.Rect = .{
        .x = relW(0.08),
        .y = relH(0.2),
        .width = relW(0.35),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

    const usbRect: UI.Rect = .{
        .x = isoRect.x + isoRect.width + relW(0.04),
        .y = relH(0.2),
        .width = relW(0.20),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

    const flashRect: UI.Rect = .{
        .x = usbRect.x + usbRect.width + relW(0.04),
        .y = relH(0.2),
        .width = relW(0.20),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

    // Main application GUI.loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        //--- @UPDATE ----------------------------------------------------------------------
        componentRegistry.processUpdates();
        //--- @ENDUPDATE -------------------------------------------------------------------

        //----------------------------------------------------------------------------------
        //--- @DRAW ------------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        rl.beginDrawing();

        rl.clearBackground(backgroundColor);

        isoRect.draw();
        usbRect.draw();
        flashRect.draw();

        rl.drawText("freetracer", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035)), 22, .white);
        rl.drawText("free and open-source by orbitixx", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035) + 23), 14, .light_gray);

        componentRegistry.processRendering();

        defer rl.endDrawing();
        //--- @ENDDRAW----------------------------------------------------------------------

    }

    // try IsoParser.parseIso(&allocator, path);
    // try IsoWriter.write(path, "/dev/sdb");

    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/alpine.iso");
    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/tinycore.iso");
    //
    //

    // const usbStorageDevices = IOKit.getUSBStorageDevices(&allocator) catch blk: {
    //     debug.print("\nWARNING: Unable to capture USB devices. Please make sure a USB flash drive is plugged in.");
    //     break :blk std.ArrayList(MacOS.USBStorageDevice).init(allocator);
    // };
    //
    // defer usbStorageDevices.deinit();
    //
    // if (usbStorageDevices.items.len > 0) {
    //     if (std.mem.count(u8, usbStorageDevices.items[0].bsdName, "disk4") > 0) {
    //         debug.print("\nFound disk4 by literal. Preparing to unmount...");
    //         DiskArbitration.unmountAllVolumes(&usbStorageDevices.items[0]) catch |err| {
    //             debug.printf("\nERROR: Failed to unmount volumes on {s}. Error message: {any}", .{ usbStorageDevices.items[0].bsdName, err });
    //         };
    //     }
    // }
    //
    // defer {
    //     for (usbStorageDevices.items) |usbStorageDevice| {
    //         usbStorageDevice.deinit();
    //     }
    // }

    debug.print("\n");
}

pub fn relW(x: f32) f32 {
    return (WINDOW_WIDTH * x);
}

pub fn relH(y: f32) f32 {
    return (WINDOW_HEIGHT * y);
}

pub const ComponentRegistry = struct {
    components: std.ArrayList(*Component),
    allocator: std.mem.Allocator,

    pub fn registerComponent(self: *ComponentRegistry, allocator: std.mem.Allocator, pAppController: *AppController, component: Component) *Component {
        const componentPointer = allocator.create(Component) catch |err| {
            debug.printf("\nERROR: ComponentRegistry is unable to successfully create a pointer to Component. Error message: {any}", .{err});
            std.debug.panic("\nUnable to allocate memory for Component in ComponentRegistry. Error: {any}", .{err});
        };

        component.setAppController(pAppController);

        componentPointer.* = component;

        self.components.append(componentPointer) catch |err| {
            debug.printf("\nERROR: ComponentRegistry unable to register component. Error message: {any}", .{err});
            std.debug.panic("\nComponentRegistry unable to register component. Error: {any}", .{err});
        };

        return componentPointer;
    }

    pub fn processUpdates(self: *ComponentRegistry) void {
        for (self.components.items) |pComponent| {
            pComponent.*.update();
        }
    }

    pub fn processRendering(self: *ComponentRegistry) void {
        for (self.components.items) |pComponent| {
            pComponent.*.draw();
        }
    }

    pub fn deinit(self: *ComponentRegistry) void {
        for (self.components.items) |pComponent| {
            pComponent.*.deinit();

            self.allocator.destroy(pComponent);
        }
        self.components.deinit();
    }
};
