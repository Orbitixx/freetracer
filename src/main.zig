const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
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

const AppObserver = @import("observers/AppObserver.zig").AppObserver;

const Component = @import("components/Component.zig");
const ComponentID = @import("components/Registry.zig").ComponentID;
const ComponentRegistry = @import("components/Registry.zig").ComponentRegistry;

const FilePickerComponent = @import("components/FilePicker/Component.zig");
const USBDevicesListComponent = @import("components/USBDevicesList/Component.zig");

// const ArgValidator = struct {
//     isoPath: bool = false,
//     devicePath: bool = false,
// };

const WINDOW_WIDTH_FACTOR: f32 = 0.5;
const WINDOW_HEIGHT_FACTOR: f32 = 0.5;

var Window: UI.Window = .{
    .width = 0,
    .height = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    performPrivilegedTask();

    rl.initWindow(Window.width, Window.height, "");
    defer rl.closeWindow(); // Close window and OpenGL context

    const m = rl.getCurrentMonitor();
    const mWidth = rl.getMonitorWidth(m);
    const mHeight = rl.getMonitorHeight(m);

    Window.width = @intFromFloat(@as(f32, @floatFromInt(mWidth)) * WINDOW_WIDTH_FACTOR);
    Window.height = @intFromFloat(@as(f32, @floatFromInt(mHeight)) * WINDOW_HEIGHT_FACTOR);

    debug.printf("\nWINDOW INITIALIZED: {d}x{d}\n", .{ Window.width, Window.height });

    rl.setWindowSize(Window.width, Window.height);
    rl.setWindowPosition(
        @as(i32, @divTrunc(mWidth, 2) - @divTrunc(Window.width, 2)),
        @as(i32, @divTrunc(mHeight, 2) - @divTrunc(Window.height, 2)),
    );

    // LOAD FONTS HERE

    rl.setTargetFPS(60);

    var buffer: [40]u8 = undefined;

    const result = try std.fmt.bufPrintZ(&buffer, "{s} {s} - {d}", .{ "Hello", "world", 4 });

    debug.printf("{s}", .{result});

    //--------------------------------------------------------------------------------------

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    //--- @COMPONENTS ----------------------------------------------------------------------

    var componentRegistry: ComponentRegistry = .{ .components = std.AutoHashMap(ComponentID, Component).init(allocator) };
    defer componentRegistry.deinit();

    const appObserver: AppObserver = .{ .componentRegistry = &componentRegistry };

    componentRegistry.registerComponent(
        ComponentID.ISOFilePicker,
        FilePickerComponent.init(allocator, &appObserver).asComponent(),
    );

    componentRegistry.registerComponent(
        ComponentID.USBDevicesList,
        USBDevicesListComponent.init(allocator, &appObserver).asComponent(),
    );

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

        // rl.drawText(
        //     str,
        //     450,
        //     150,
        //     20,
        //     .white,
        // );

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
    return (@as(f32, @floatFromInt(Window.width)) * x);
}

pub fn relH(y: f32) f32 {
    return (@as(f32, @floatFromInt(Window.height)) * y);
}

pub fn performPrivilegedTask() void {
    const idString = "com.orbitixx.freetracer-helper";

    const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        idString,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );
    defer _ = c.CFRelease(portNameRef);

    const remoteMessagePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, portNameRef);

    if (remoteMessagePort == null) {
        std.log.err("Freetracer unable to create a remote message port to Freetracer Helper Tool.", .{});
        return;
    }

    defer _ = c.CFRelease(remoteMessagePort);

    const dataPayload: i32 = 200;
    const dataPayloadBytePtr: [*c]const u8 = @ptrCast(&dataPayload);

    const requestDataRef: c.CFDataRef = c.CFDataCreate(c.kCFAllocatorDefault, dataPayloadBytePtr, @sizeOf(i32));
    defer _ = c.CFRelease(requestDataRef);

    var responseCode: c.SInt32 = 0;
    var responseData: c.CFDataRef = null;

    const kSendTimeoutInSeconds: f64 = 5.0;
    const kReceiveTimeoutInSeconds: f64 = 5.0;
    const kUnmountDiskRequest: i32 = 101;

    responseCode = c.CFMessagePortSendRequest(
        remoteMessagePort,
        kUnmountDiskRequest,
        requestDataRef,
        kSendTimeoutInSeconds,
        kReceiveTimeoutInSeconds,
        c.kCFRunLoopDefaultMode,
        &responseData,
    );

    if (responseCode != c.kCFMessagePortSuccess or responseData == null) {
        std.log.err(
            "Freetracer failed to communicate with Freetracer Helper Tool - received invalid response code ({d}) or null response data {any}",
            .{ responseCode, responseData },
        );
        return;
    }

    var result: i32 = -1;

    if (c.CFDataGetLength(responseData) >= @sizeOf(i32)) {
        const dataPtr = c.CFDataGetBytePtr(responseData);
        const resultPtr: *const i32 = @ptrCast(@alignCast(dataPtr));
        result = resultPtr.*;
    }

    if (result == 0) std.log.info("Freetracer successfully received reseponse from Freetracer Helper Tool: {d}", .{result}) else {
        std.log.err("Freetracer recieved unsuccessful response from Freetracer Helper Tool: {d}.", .{result});
        return;
    }
}
