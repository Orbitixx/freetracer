const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
const osd = @import("osdialog");

const Logger = @import("./lib/util/logger.zig").LoggerSingleton;

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

    try Logger.init(allocator);
    errdefer Logger.deinit();
    defer Logger.deinit();

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

    var helperResponse: bool = false;

    if (!isHelperToolInstalled()) {
        helperResponse = installPrivilegedHelperTool();
        if (helperResponse) helperResponse = performPrivilegedTask();
    } else helperResponse = true;

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

        rl.drawText(
            if (helperResponse) "HELPER SUCCESS" else "HELPER FAILED",
            @intFromFloat(relW(0.86)),
            @intFromFloat(relH(0.035)),
            12,
            if (helperResponse) .green else .red,
        );

        // Logger.log("Hello test", .{});

        // _ = std.fmt.bufPrintZ(
        //     &buffer,
        //     Logger.getLatestLog(),
        //     .{},
        // ) catch |err| {
        //     std.debug.panic("\n{any}", .{err});
        // };
        //

        // var strBuf: [256]u8 = undefined;
        // const str: [:0]const u8 = try allocator. (Logger.getLatestLog(), &strBuf);
        // const latestLogLine = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, str, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);

        rl.drawText(
            Logger.getLatestLog(),
            @intFromFloat(relW(0.02)),
            @intFromFloat(relH(0.95)),
            13,
            .white,
        );

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

pub fn installPrivilegedHelperTool() bool {
    const kHelperToolBundleId = "com.orbitixx.freetracer-helper";
    // const kMainAppBundleId = "com.orbitixx.freetracer";

    var installStatus: c.Boolean = c.FALSE;

    debug.print("Install Helper Tool: attempting to obtain initial (empty) authorization.");

    var authRef: c.AuthorizationRef = undefined;
    var authStatus: c.OSStatus = c.AuthorizationCreate(null, null, 0, &authRef);

    if (authStatus != c.errAuthorizationSuccess) {
        debug.printf("Freetracer failed to obtain empty authorization in the process of installing its privileged helper tool. AuthStatus: {d}.", .{authStatus});
        authRef = null;
        return false;
    }

    debug.print("Install Helper Tool: successfully obtained an empty authorization.");

    defer _ = c.AuthorizationFree(authRef, c.kAuthorizationFlagDefaults);

    var authItem = c.AuthorizationItem{ .name = c.kSMRightBlessPrivilegedHelper, .flags = 0, .value = null, .valueLength = 0 };

    const authRights: c.AuthorizationRights = .{ .count = 1, .items = &authItem };
    const authFlags: c.AuthorizationFlags = c.kAuthorizationFlagDefaults | c.kAuthorizationFlagInteractionAllowed | c.kAuthorizationFlagPreAuthorize | c.kAuthorizationFlagExtendRights;

    debug.print("Install Helper Tool: attempting to copy authorization rights to authorization ref.");

    authStatus = c.AuthorizationCopyRights(authRef, &authRights, null, authFlags, null);

    if (authStatus != c.errAuthorizationSuccess) {
        debug.printf("Freetracer failed to obtain specific authorization rights in the process of installing its privileged helper tool. AuthStatus: {d}.", .{authStatus});
        return false;
    }

    debug.print("Install Helper Tool: successfully copied auth rights; attempting to create a bundle id CFStringRef.");

    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, kHelperToolBundleId, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(helperLabel);

    debug.print("Install Helper Tool: successfully created a bundle id CFStringRef.");

    var cfError: c.CFErrorRef = null;

    debug.print("Install Helper Tool: launching SMJobBless call on the helper.");

    installStatus = c.SMJobBless(c.kSMDomainSystemLaunchd, helperLabel, authRef, &cfError);

    debug.print("Install Helper Tool: SMJobBless call completed without kernel panicking.");

    if (installStatus == c.TRUE) {
        debug.printf("Freetracer successfully installed its privileged helper tool.", .{});
        return true;
    }

    debug.print("Install Helper Tool: SMJobBless call failed, proceeding to analyze error.");

    if (cfError == null) {
        debug.printf("Freetracer failed to install its privileged helper tool without any error status from SMJobBless.", .{});
        return false;
    }

    defer _ = c.CFRelease(cfError);

    debug.print("Install Helper Tool: attempting to copy error description.");

    const errorDesc = c.CFErrorCopyDescription(cfError);

    if (errorDesc == null) {
        debug.printf("Freetracer could not copy error description from the SMJobBless operation error, error description is null.", .{});
        return false;
    }

    debug.print("Install Helper Tool: obtained a copy of error description.");

    defer _ = c.CFRelease(errorDesc);

    debug.print("Install Helper Tool: attempting to obtain a string from error description.");

    var errDescBuffer: [512]u8 = undefined;
    const obtainErrorDescStatus = c.CFStringGetCString(errorDesc, &errDescBuffer, errDescBuffer.len, c.kCFStringEncodingUTF8);

    if (obtainErrorDescStatus == 0) {
        debug.printf("Freetracer could not obtain error description from the SMJobBless operation error, error description is NOT null.", .{});
        return false;
    }

    debug.printf("Freetracer received SMJobBless error: {s}.", .{std.mem.sliceTo(&errDescBuffer, 0)});
    return false;
}

pub fn isHelperToolInstalled() bool {
    const kHelperToolBundleId = "com.orbitixx.freetracer-helper";
    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, kHelperToolBundleId, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(helperLabel);

    const smJobCopyDict = c.SMJobCopyDictionary(c.kSMDomainSystemLaunchd, helperLabel);

    if (smJobCopyDict == null) {
        debug.printf("isHelperToolInstalled(): the SMJobCopyDictionary for helper tool is NULL. Helper tool is NOT installed.", .{});
        return false;
    }

    defer _ = c.CFRelease(smJobCopyDict);

    debug.printf("isHelperToolInstalled(): Helper tool found, it appears to be installed.", .{});
    return true;
}

pub fn performPrivilegedTask() bool {
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
        debug.printf("Freetracer unable to create a remote message port to Freetracer Helper Tool.", .{});
        return false;
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
        debug.printf(
            "Freetracer failed to communicate with Freetracer Helper Tool - received invalid response code ({d}) or null response data {any}",
            .{ responseCode, responseData },
        );
        return false;
    }

    var result: i32 = -1;

    if (c.CFDataGetLength(responseData) >= @sizeOf(i32)) {
        const dataPtr = c.CFDataGetBytePtr(responseData);
        const resultPtr: *const i32 = @ptrCast(@alignCast(dataPtr));
        result = resultPtr.*;
    }

    if (result == 0) {
        debug.printf("Freetracer successfully received reseponse from Freetracer Helper Tool: {d}", .{result});
        return true;
    } else {
        debug.printf("Freetracer recieved unsuccessful response from Freetracer Helper Tool: {d}.", .{result});
        return false;
    }
}
