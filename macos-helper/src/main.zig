const std = @import("std");
const env = @import("env.zig");
const testing = std.testing;
const freetracer_lib = @import("freetracer-lib");

const Debug = freetracer_lib.Debug;
const xpc = freetracer_lib.xpc;

const k = freetracer_lib.k;
const c = freetracer_lib.c;
const String = freetracer_lib.String;
const Character = freetracer_lib.Character;

const MachCommunicator = freetracer_lib.MachCommunicator;
const XPCService = freetracer_lib.XPCService;
const XPCConnection = freetracer_lib.XPCConnection;
const XPCObject = freetracer_lib.XPCObject;

const HelperRequestCode = freetracer_lib.HelperRequestCode;
const HelperResponseCode = freetracer_lib.HelperResponseCode;
const ReturnCode = freetracer_lib.HelperReturnCode;
const SerializedData = freetracer_lib.SerializedData;
const WriteRequestData = freetracer_lib.WriteRequestData;

var queuedUnmounts: i32 = 0;

pub const WRITE_BLOCK_SIZE = 4096;

fn xpcRequestHandler(connection: XPCConnection, message: XPCObject) callconv(.c) void {
    Debug.log(.INFO, "Helper received a new message over XPC bridge. Attempting to authenticate requester...", .{});

    const isConnectionAuthentic: bool = XPCService.authenticateMessage(message, @ptrCast(env.MAIN_APP_BUNDLE_ID));

    if (!isConnectionAuthentic) {
        Debug.log(.ERROR, "XPC message failed authentication. Dropping request...", .{});
        return;
    } else Debug.log(.INFO, "Successfully authenticated incoming message...", .{});

    if (message == null) {
        Debug.log(.ERROR, "XPC Server received a NULL request. Aborting processing response...", .{});
        return;
    }

    const msg_type = xpc.xpc_get_type(message);

    if (msg_type == xpc.XPC_TYPE_DICTIONARY) {
        processRequestMessage(connection, message);
    } else if (msg_type == xpc.XPC_TYPE_ERROR) {
        Debug.log(.ERROR, "An error occurred attemting to run a message handler callback.", .{});
    } else {
        Debug.log(.ERROR, "XPC Server received an unknown message type.", .{});
    }

    Debug.log(.INFO, "Finished processing request", .{});
}

fn processRequestMessage(connection: XPCConnection, data: XPCObject) void {
    const request: HelperRequestCode = XPCService.parseRequest(data);

    Debug.log(.INFO, "Received request: {any}", .{request});

    switch (request) {
        .INITIAL_PING => processInitialPing(connection),
        .GET_HELPER_VERSION => processGetHelperVersion(connection),
        .UNMOUNT_DISK => processRequestUnmount(connection, data),
        .WRITE_ISO_TO_DEVICE => {},
    }
}

fn processInitialPing(connection: XPCConnection) void {
    const reply = XPCService.createResponse(.INITIAL_PONG);
    defer XPCService.releaseObject(reply);
    XPCService.connectionSendMessage(connection, reply);
}

fn processGetHelperVersion(connection: XPCConnection) void {
    const reply = XPCService.createResponse(.HELPER_VERSION_OBTAINED);
    defer XPCService.releaseObject(reply);
    XPCService.createString(reply, "version", @ptrCast(env.HELPER_VERSION));
    XPCService.connectionSendMessage(connection, reply);
}

fn processRequestUnmount(connection: XPCConnection, data: XPCObject) void {

    // TODO: validate and sanitize disk input
    // string conforms to /dev/diskX or /dev/rdiskX format
    // wihtin unmount: ensure disk is 1) external and 2) safe to unmount/eject

    const disk = XPCService.parseString(data, "disk");
    const result = handleDiskUnmountRequest(disk);

    var response: XPCObject = undefined;

    if (result != .SUCCESS) {
        Debug.log(.ERROR, "Failed to unmount specified disk, error code: {any}", .{result});
        response = XPCService.createResponse(.DISK_UNMOUNT_FAIL);
    } else response = XPCService.createResponse(.DISK_UNMOUNT_SUCCESS);

    XPCService.connectionSendMessage(connection, response);
}

fn processRequestWriteISO(connection: XPCConnection, data: XPCObject) void {
    _ = connection;
    _ = data;

    // TODO: validate and sanitize file input
    // canonicalize the path to resolve any symbolic links and ensure it does not
    // point to a sensitive system file (e.g., /etc/passwd, /dev/random).

    // TODO:
    // use the Disk Arbitration framework to acquire an exclusive lock on the physical disk before writing.
    //
    // TODO:
    // To prevent the operating system from automatically remounting volumes while the raw write is in progress,
    // the helper should also register a DADissenter for the disk. This temporarily blocks mount attempts from other processes,
    // ensuring an exclusive lock on the device during the critical write phase.
}

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    defer {
        _ = debugAllocator.detectLeaks();
        _ = debugAllocator.deinit();
    }

    // Initialize Debug singleton
    try Debug.init(allocator, .{});
    defer Debug.deinit();

    Debug.log(.INFO, "------------------------------------------------------------------------------------------", .{});
    Debug.log(.INFO, "Debug logger is initialized.", .{});

    var xpcServer = try XPCService.init(.{
        .isServer = true,
        .serviceName = "Freetracer Helper XPC Server",
        .serverBundleId = @ptrCast(env.BUNDLE_ID),
        .requestHandler = @ptrCast(&xpcRequestHandler),
    });
    defer xpcServer.deinit();

    xpcServer.start();

    // var machCommunicator = MachCommunicator.init(allocator, .{
    //     .localBundleId = env.BUNDLE_ID,
    //     .remoteBundleId = env.MAIN_APP_BUNDLE_ID,
    //     .ownerName = "Freetracer Helper Tool",
    //     .processMessageFn = processRequestMessage,
    // });
    //
    // defer machCommunicator.deinit();
    // try machCommunicator.start();

    // TODO:The launchd.plist should be configured for on-demand launch, and the tool should exit after completing its work.
    Debug.log(.INFO, "Helper tool successfully terminated.", .{});
}

// fn processRequestMessage(msgId: i32, requestData: SerializedData) !SerializedData {
//     var responseData: SerializedData = undefined;
//
//     switch (msgId) {
//         //
//         k.HelperVersionRequest => {
//             Debug.log(.INFO, "Freetracer Helper Tool received a version query request [{d}].", .{k.HelperVersionRequest});
//
//             const versionString = handleHelperVersionCheckRequest();
//             Debug.log(.INFO, "Packing size of versionString: {d}", .{@sizeOf(@TypeOf(env.HELPER_VERSION))});
//             responseData = try SerializedData.serialize([:0]const u8, versionString);
//         },
//
//         k.UnmountDiskRequest => {
//             Debug.log(.INFO, "Freetracer Helper Tool received DADiskUnmount() request [{d}].", .{k.UnmountDiskRequest});
//
//             const responseCode = handleDiskUnmountRequest(requestData);
//
//             Debug.log(.WARNING, "responseCode is: {d}", .{@intFromEnum(responseCode)});
//
//             responseData = try SerializedData.serialize(ReturnCode, responseCode);
//         },
//
//         k.WriteISOToDeviceRequest => {
//             Debug.log(.INFO, "Freetracer Helper Tool received WriteISOToDeviceRequest [{d}].", .{k.WriteISOToDeviceRequest});
//
//             const responseCode = handleWriteISOToDeviceRequest(requestData);
//             responseData = try SerializedData.serialize(ReturnCode, responseCode);
//         },
//
//         else => {
//             Debug.log(.WARNING, "Freetracer Helper Tool received unknown request: {d}. Ignoring request...", .{msgId});
//         },
//     }
//
//     return responseData;
// }
//
fn handleHelperVersionCheckRequest() [:0]const u8 {
    return env.HELPER_VERSION;
}

// fn handleDiskUnmountRequest(requestData: SerializedData) ReturnCode {
fn handleDiskUnmountRequest(targetDisk: []const u8) ReturnCode {

    // TODO: perform a check to ensure the device has a kIOMediaRemovableKey key

    if (targetDisk.len < 2) return ReturnCode.FAILED_TO_CREATE_DA_DISK_REF;

    Debug.log(.INFO, "Received bsdName: {s}", .{targetDisk});

    // const bsdName = std.mem.sliceTo(&requestData.data, 0x00);
    const bsdName = std.mem.sliceTo(targetDisk, 0x00);

    Debug.log(.INFO, "Received bsdName: {s}", .{bsdName});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) {
        Debug.log(.ERROR, "Failed to create DASession\n", .{});
        return ReturnCode.FAILED_TO_CREATE_DA_SESSION;
    }
    defer _ = c.CFRelease(daSession);

    Debug.log(.INFO, "Successfully started a blank DASession.", .{});

    const currentLoop = c.CFRunLoopGetCurrent();

    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    // Ensure unscheduling happens before the session is released
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    Debug.log(.INFO, "DASession is successfully scheduled with the run loop.", .{});

    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, bsdName.ptr);

    if (daDiskRef == null) {
        Debug.log(.ERROR, "Could not create DADiskRef for '{s}', skipping.\n", .{bsdName});
        return ReturnCode.FAILED_TO_CREATE_DA_DISK_REF;
    }
    defer _ = c.CFRelease(daDiskRef);

    Debug.log(.INFO, "DA Disk refererence is successfuly created for the provided device BSD name.", .{});

    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));

    if (diskInfo == null) return ReturnCode.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    defer _ = c.CFRelease(diskInfo);

    Debug.log(.INFO, "DA Disk Description is successfully obtained/copied.", .{});

    // _ = c.CFShow(diskInfo);

    // NOTE: Not sure that it is appropriate to run an EFI check against a whole device, instead of a leaf.
    // Probably no value in doing so, unless the unmount is processed separately for each leaf volume.
    //
    // Debug.log(.DEBUG, "Running a check for an EFI partition...", .{});
    //
    // // --- @PROP: Check for EFI parition ---------------------------------------------------
    // // Do not release efiKey, release causes segmentation fault
    // const efiKeyRef: c.CFStringRef = @ptrCast(@alignCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionVolumeNameKey)));
    //
    // if (efiKeyRef == null) return ReturnCode.FAILED_TO_OBTAIN_EFI_KEY_STRING;
    //
    // std.log.info("\nEfi Key String: {any}", .{efiKeyRef});
    //
    // Debug.log(.DEBUG, "First intermediate EFI check log", .{});
    //
    // var efiKeyBuf: [255]u8 = std.mem.zeroes([255]u8);
    // const efiKeyResult: c.Boolean = c.CFStringGetCString(efiKeyRef, &efiKeyBuf, efiKeyBuf.len, c.kCFStringEncodingUTF8);
    //
    // if (efiKeyResult == 0 or efiKeyRef == null or c.CFGetTypeID(efiKeyRef) != c.CFStringGetTypeID()) {
    //     return ReturnCode.FAILED_TO_OBTAIN_EFI_KEY_STRING;
    // }
    //
    // Debug.log(.DEBUG, "Second intermediate EFI check log", .{});
    //
    // const isEfi = std.mem.count(u8, &efiKeyBuf, "EFI") > 0;
    // // --- @ENDPROP: EFI
    //
    // Debug.log(.INFO, "Finished checking for an EFI partition... Checking if the device is an internal device...", .{});

    // --- @PROP: Check for DeviceInternal ---------------------------------------------------
    const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionDeviceInternalKey));

    if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
        return ReturnCode.FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY_BOOL;
    }

    const isInternalDevice: bool = (isInternalDeviceRef == c.kCFBooleanTrue);
    // --- @ENDPROP: DeviceInternal

    Debug.log(.INFO, "Finished checking for an internal device...", .{});

    if (isInternalDevice) {
        Debug.log(.ERROR, "ERROR: internal device detected on disk: {s}. Aborting unmount operations for device.", .{bsdName});
        return ReturnCode.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;
    }

    // if (isEfi) {
    //     std.log.warn("Skipping unmount because of a potential EFI partition on disk: {s}.", .{bsdName});
    //     return ReturnCode.SKIPPED_UNMOUNT_ATTEMPT_ON_EFI_PARTITION;
    // }

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, &queuedUnmounts);

    // TODO: code below appears to be useless
    queuedUnmounts += 1;

    if (queuedUnmounts > 0) {
        c.CFRunLoopRun();
    } else {
        Debug.log(.ERROR, "No valid unmount calls could be initiated for device: {s}.", .{bsdName});
    }

    return ReturnCode.SUCCESS;
}

fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    _ = context;
    // if (context == null) {
    //     Debug.log(.ERROR, "\nERROR: Unmount callback returned NULL context.");
    //     return;
    // }

    // const counter_ptr: *u8 = @ptrCast(context);
    // _ = context;

    // const bsdName = if (c.DADiskGetBSDName(disk)) |name| std.mem.sliceTo(name, 0) else "Unknown Disk";

    Debug.log(.INFO, "Processing unmountDiskCallback()...", .{});

    const bsdNameCPtr = c.DADiskGetBSDName(disk);

    const bsdName: [:0]const u8 = @ptrCast(std.mem.sliceTo(bsdNameCPtr, 0x00));

    if (bsdName.len == 0) {
        Debug.log(.WARNING, "unmountDiskCallback(): bsdName received is of 0 length.", .{});
    }

    if (dissenter != null) {
        Debug.log(.WARNING, "Disk Arbitration Dissenter returned a non-empty status.", .{});

        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusString: [256]u8 = undefined;

        if (statusStringRef != null) {
            _ = c.CFStringGetCString(statusStringRef, &statusString, statusString.len, c.kCFStringEncodingUTF8);
        }
        Debug.log(.ERROR, "Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusString });
    } else {
        Debug.log(.INFO, "Successfully unmounted disk: {s}", .{bsdName});
        queuedUnmounts -= 1;
    }

    if (queuedUnmounts == 0) {
        Debug.log(.INFO, "Finished unmounting all volumes for device.", .{});

        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}

fn handleWriteISOToDeviceRequest(requestData: SerializedData) ReturnCode {
    const data: [k.MachPortPacketSize]u8 = SerializedData.deserialize([k.MachPortPacketSize]u8, requestData) catch |err| {
        Debug.log(.ERROR, "Unable to deserialize WriteRequestData. Error: {any}", .{err});
        return ReturnCode.FAILED_TO_WRITE_ISO_TO_DEVICE;
    };

    Debug.log(.INFO, "Received data: {s}", .{requestData.data});

    // Splitting "isoPathString;devicePathString" apart
    const isoPath: [k.MachPortPacketSize]u8 = String.parseUpToDelimeter(
        k.MachPortPacketSize,
        data,
        Character.SEMICOLON,
    );

    const devicePath: [k.MachPortPacketSize]u8 = String.parseAfterDelimeter(
        k.MachPortPacketSize,
        data,
        Character.SEMICOLON,
        Character.NULL,
    );

    Debug.log(.INFO, "handleWriteISOToDeviceRequest(): \n\tisoPath: {s}\n\tdevicePath: {s}", .{ isoPath, devicePath });

    // TODO: launch on its own thread, such that the main thread may respond to status requests
    writeISO(std.mem.sliceTo(&isoPath, Character.NULL), std.mem.sliceTo(&devicePath, Character.NULL)) catch |err| {
        Debug.log(.ERROR, "Unable to write to device. Error: {any}", .{err});
        return ReturnCode.FAILED_TO_WRITE_ISO_TO_DEVICE;
    };

    return ReturnCode.SUCCESS;
}

fn writeISO(isoPath: []const u8, devicePath: []const u8) !void {
    Debug.log(.DEBUG, "Begin writing prep...", .{});
    var writeBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const isoFile: std.fs.File = try std.fs.cwd().openFile(isoPath, .{ .mode = .read_only });
    defer isoFile.close();

    const device = try std.fs.openFileAbsolute(devicePath, .{ .mode = .read_write });
    defer device.close();

    const fileStat = try isoFile.stat();
    const ISO_SIZE = fileStat.size;

    defer Debug.log(.INFO, "Write finished executing...", .{});

    var currentByte: u64 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{ISO_SIZE});

    Debug.log(.INFO, "Writing ISO to device, please wait...", .{});

    while (currentByte < ISO_SIZE) {
        try isoFile.seekTo(currentByte);
        const bytesRead = try isoFile.read(&writeBuffer);

        if (bytesRead == 0) {
            Debug.log(.INFO, "End of ISO File reached, final block: {d} at {d}!", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        // Important to use the slice syntax here, otherwise if writing &writeBuffer
        // it only writes WRITE_BLOCK_SIZE blocks, meaning if the last block is smaller
        // then the data will likely be corrupted.
        const bytesWritten = try device.write(writeBuffer[0..bytesRead]);

        if (bytesWritten != bytesRead or bytesWritten == 0) {
            Debug.log(.ERROR, "CRITICAL ERROR: failed to correctly write to device. Aborting...", .{});
            break;
        }

        currentByte += WRITE_BLOCK_SIZE;
    }

    try device.sync();

    Debug.log(.INFO, "Finished writing ISO image to device!", .{});
}

comptime {
    @export(
        @as([*:0]const u8, @ptrCast(env.INFO_PLIST)),
        .{ .name = "__info_plist", .section = "__TEXT,__info_plist", .visibility = .default, .linkage = .strong },
    );

    @export(
        @as([*:0]const u8, @ptrCast(env.LAUNCHD_PLIST)),
        .{ .name = "__launchd_plist", .section = "__TEXT,__launchd_plist", .visibility = .default, .linkage = .strong },
    );

    // @export(
    //     @as([*:0]const u8, @ptrCast(env.ENTITLEMENTS_PLIST)),
    //     .{ .name = "__entitlements", .section = "__TEXT,__entitlements", .visibility = .default, .linkage = .strong },
    // );
}

test "handle helper version check request" {
    const reportedVersion = handleHelperVersionCheckRequest();
    try testing.expectEqualSlices(u8, reportedVersion, env.HELPER_VERSION);
}

test "process request message: version check" {

    // Expected payload is null
    const requestData: SerializedData = try SerializedData.serialize(@TypeOf(null), null);
    const serializedResponse: SerializedData = try processRequestMessage(k.HelperVersionRequest, requestData);

    const deserializedData: [k.MachPortPacketSize]u8 = try SerializedData.deserialize([k.MachPortPacketSize]u8, serializedResponse);
    const nullIndex = std.mem.indexOfScalar(u8, deserializedData[0..], Character.NULL);

    try testing.expect(nullIndex != null);
    const version: [:0]const u8 = deserializedData[0..nullIndex.? :0];
    try testing.expectEqualSlices(u8, env.HELPER_VERSION, version);
}

test "parsing iso + device paths parsing functions" {
    // const testPathsString: [:0]const u8 = @ptrCast("testIsoString.iso;/dev/testDevicePath");
    const testPathsString: [:0]const u8 = @ptrCast("/Users/freetracer/Downloads/debian_XX_aarch64.iso;/dev/disk4");
    const serializedTestString: SerializedData = try SerializedData.serialize([:0]const u8, testPathsString);

    const isoPath: [k.MachPortPacketSize]u8 = String.parseUpToDelimeter(k.MachPortPacketSize, serializedTestString.data, Character.SEMICOLON);
    const devicePath: [k.MachPortPacketSize]u8 = String.parseAfterDelimeter(k.MachPortPacketSize, serializedTestString.data, Character.SEMICOLON, Character.NULL);

    const expectedISOPath: []const u8 = "/Users/freetracer/Downloads/debian_XX_aarch64.iso";
    const expectedDevicePath: []const u8 = "/dev/disk4";

    try testing.expectEqualSlices(u8, expectedISOPath, std.mem.sliceTo(&isoPath, Character.NULL));
    try testing.expectEqualSlices(u8, expectedDevicePath, std.mem.sliceTo(&devicePath, Character.NULL));
}

test "process request message: write iso request" {
    // const requestData: SerializedData = try SerializedData.serialize([:0]const u8, @as([:0]const u8, @ptrCast("isoPathString;devicePathString;")));
}
