const std = @import("std");
const env = @import("env.zig");
const testing = std.testing;
const freetracer_lib = @import("freetracer-lib");

const ShutdownManager = @import("./managers/ShutdownManager.zig").ShutdownManagerSingleton;
const Debug = freetracer_lib.Debug;
const xpc = freetracer_lib.xpc;
const ISOParser = freetracer_lib.ISOParser;

const k = freetracer_lib.k;
const c = freetracer_lib.c;
const String = freetracer_lib.String;
const Character = freetracer_lib.Character;

const da = @import("util/diskarbitration.zig");
const fs = @import("util/filesystem.zig");
const dev = @import("util/devices.zig");
const str = @import("util/strings.zig");

const MachCommunicator = freetracer_lib.MachCommunicator;
const XPCService = freetracer_lib.XPCService;
const XPCConnection = freetracer_lib.XPCConnection;
const XPCObject = freetracer_lib.XPCObject;

const HelperRequestCode = freetracer_lib.HelperRequestCode;
const HelperResponseCode = freetracer_lib.HelperResponseCode;
const ReturnCode = freetracer_lib.HelperReturnCode;
const SerializedData = freetracer_lib.SerializedData;
const WriteRequestData = freetracer_lib.WriteRequestData;

const WRITE_BLOCK_SIZE = 4096;
const MAX_PATH_BYTES = std.fs.max_path_bytes;

// NOTE: Critical compile-time .plist symbol exports
// Apple requires these to be linked into the binary in their respective sections
// in order for the helper to be correctly registered and launched by the system daemon.
comptime {
    @export(
        @as([*:0]const u8, @ptrCast(env.INFO_PLIST)),
        .{ .name = "__info_plist", .section = "__TEXT,__info_plist", .visibility = .default, .linkage = .strong },
    );

    @export(
        @as([*:0]const u8, @ptrCast(env.LAUNCHD_PLIST)),
        .{ .name = "__launchd_plist", .section = "__TEXT,__launchd_plist", .visibility = .default, .linkage = .strong },
    );
}

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    // TODO: swap out debug allocator for production

    try Debug.init(allocator, .{});

    // Standard daemon out log does not support .DEBUG; .INFO and above only.
    Debug.log(.INFO, "------------------------------------------------------------------------------------------", .{});
    Debug.log(.INFO, "Debug logger is initialized.", .{});

    var xpcServer = try XPCService.init(.{
        .isServer = true,
        .serviceName = "Freetracer Helper XPC Server",
        .serverBundleId = @ptrCast(env.BUNDLE_ID),
        .requestHandler = @ptrCast(&xpcRequestHandler),
    });

    // All deinit()'s are handled by the ShutdownManager because XPC's
    // main dispatch queue is thread-blocking and it never returns.
    ShutdownManager.init(&debugAllocator, &xpcServer);
    // Should never execute in production, but just in case as a safeguard.
    defer ShutdownManager.terminateWithError(error.HelperProcessUnexpectedlyTerminatedFromMain);

    // Thread-blocking queue dispatch; never returns -- must be forcefully interrupted.
    xpcServer.start();
}

/// C-convention callback; called anytime a message is received over the XPC connection.
fn xpcRequestHandler(connection: XPCConnection, message: XPCObject) callconv(.c) void {
    Debug.log(.INFO, "Helper received a new message over XPC bridge. Attempting to authenticate requester...", .{});

    const isConnectionAuthorized: bool = XPCService.authenticateMessage(
        message,
        @ptrCast(env.MAIN_APP_BUNDLE_ID),
        @ptrCast(env.MAIN_APP_TEAM_ID),
    );

    if (!isConnectionAuthorized) {
        Debug.log(.ERROR, "XPC message failed authentication. Dropping request...", .{});
        ShutdownManager.terminateWithError(error.XPC_CONNECTION_UNAUTHORIZED);
        return;
    } else Debug.log(.INFO, "Successfully authenticated incoming message...", .{});

    if (message == null) {
        Debug.log(.ERROR, "XPC Server received a NULL request. Aborting processing response...", .{});
        ShutdownManager.terminateWithError(error.XPC_MESSAGE_PAYLOAD_NULL);
        return;
    }

    const msg_type = xpc.xpc_get_type(message);

    if (msg_type == xpc.XPC_TYPE_DICTIONARY) {
        processRequestMessage(connection, message);
    } else if (msg_type == xpc.XPC_TYPE_ERROR) {
        Debug.log(.ERROR, "An error occurred attemting to run a message handler callback.", .{});
        ShutdownManager.terminateWithError(error.XPC_ERROR_RUNNING_MESSAGE_CALLBACK);
    } else {
        Debug.log(.ERROR, "XPC Server received an unknown message type.", .{});
        ShutdownManager.terminateWithError(error.XPC_UNKNOWN_ERROR_ON_CALLBACK);
    }

    Debug.log(.INFO, "Finished processing request", .{});
}

/// Zig-native message callback processor function, called by the C-conv callback: xpcRequestHandler
fn processRequestMessage(connection: XPCConnection, data: XPCObject) void {
    const request: HelperRequestCode = XPCService.parseRequest(data);

    Debug.log(.INFO, "Received request: {any}", .{request});

    switch (request) {
        .INITIAL_PING => processInitialPing(connection),
        .GET_HELPER_VERSION => processGetHelperVersion(connection),
        .UNMOUNT_DISK => Debug.log(.INFO, "Discrete unmount request received -- dropping request. Deprecated.", .{}),
        .WRITE_ISO_TO_DEVICE => processRequestWriteISO(connection, data),
    }
}

fn processInitialPing(connection: XPCConnection) void {
    const reply: XPCObject = XPCService.createResponse(.INITIAL_PONG);
    defer XPCService.releaseObject(reply);
    XPCService.connectionSendMessage(connection, reply);
}

fn processGetHelperVersion(connection: XPCConnection) void {
    const reply: XPCObject = XPCService.createResponse(.HELPER_VERSION_OBTAINED);
    defer XPCService.releaseObject(reply);
    XPCService.createString(reply, "version", @ptrCast(env.HELPER_VERSION));
    XPCService.connectionSendMessage(connection, reply);
}

fn handleHelperVersionCheckRequest() [:0]const u8 {
    return env.HELPER_VERSION;
}

fn attemptDiskUnmount(connection: XPCConnection, data: XPCObject) bool {
    const disk: []const u8 = XPCService.parseString(data, "disk");

    if (!str.isDiskStringValid(disk)) {
        Debug.log(.ERROR, "Received/parsed disk string is invalid: {s}. Aborting processing request...", .{disk});
        ShutdownManager.terminateWithError(error.REQUEST_DISK_UNMOUNT_DISK_STRING_INVALID);
        return false;
    }

    const result = dev.requestUnmountWithIORegistry(disk);

    var response: XPCObject = undefined;

    if (result != .SUCCESS) {
        Debug.log(.ERROR, "Failed to unmount specified disk, error code: {any}", .{result});
        response = XPCService.createResponse(.DISK_UNMOUNT_FAIL);
        ShutdownManager.terminateWithError(error.REQUEST_DISK_UNMOUNT_FAILED_TO_UNMOUNT_DISK);
    } else {
        response = XPCService.createResponse(.DISK_UNMOUNT_SUCCESS);
    }

    Debug.log(.INFO, "Finished executing unmount task, sending response ({any}) to the client.", .{result});

    XPCService.connectionSendMessage(connection, response);

    if (result == .SUCCESS) return true else return false;
}

fn processRequestWriteISO(connection: XPCConnection, data: XPCObject) void {
    //
    const isoPath: []const u8 = XPCService.parseString(data, "isoPath");
    const deviceBsdName: []const u8 = XPCService.parseString(data, "disk");
    // const deviceServiceId: u64 = XPCService.getUInt64(data, "deviceServiceId");

    const userHomePath: []const u8 = XPCService.getUserHomePath(connection) catch |err| {
        Debug.log(.ERROR, "Unable to retrieve user home path. Error: {any}", .{err});
        const xpcErrorResponse = XPCService.createResponse(.ISO_WRITE_FAIL);
        defer XPCService.releaseObject(xpcErrorResponse);
        XPCService.connectionSendMessage(connection, xpcErrorResponse);
        ShutdownManager.terminateWithError(err);
        return;
    };

    const isoFile = fs.openFileValidated(isoPath, .{ .userHomePath = userHomePath }) catch |err| {
        Debug.log(.ERROR, "Unable to safely open provided ISO file path: {s}, validation error: {any}", .{ isoPath, err });
        const xpcErrorResponse = XPCService.createResponse(.ISO_FILE_INVALID);
        defer XPCService.releaseObject(xpcErrorResponse);
        XPCService.connectionSendMessage(connection, xpcErrorResponse);
        ShutdownManager.terminateWithError(err);
        return;
    };

    defer isoFile.close();

    Debug.log(.INFO, "ISO File is determined to be valid.", .{});
    const xpcReply: XPCObject = XPCService.createResponse(.ISO_FILE_VALID);
    defer XPCService.releaseObject(xpcReply);
    XPCService.connectionSendMessage(connection, xpcReply);

    const device = dev.openDeviceValidated(deviceBsdName) catch |err| {
        // TODO: sanitize device name before logging
        Debug.log(.ERROR, "Unable to safely open device: {s}, validation error: {any}", .{ deviceBsdName, err });
        const xpcErrorResponse = XPCService.createResponse(.DEVICE_INVALID);
        defer XPCService.releaseObject(xpcErrorResponse);
        XPCService.connectionSendMessage(connection, xpcErrorResponse);
        ShutdownManager.terminateWithError(err);
        return;
    };

    defer device.close();

    fs.writeISO(connection, isoFile, device) catch |err| {
        Debug.log(.ERROR, "Unable to safely open provided ISO file path: {s}, validation error: {any}", .{ isoPath, err });
        const xpcErrorResponse = XPCService.createResponse(.ISO_FILE_INVALID);
        defer XPCService.releaseObject(xpcErrorResponse);
        XPCService.connectionSendMessage(connection, xpcErrorResponse);
        ShutdownManager.terminateWithError(err);
        return;
    };

    ShutdownManager.exitSuccessfully();

    // TODO:
    // To prevent the operating system from automatically remounting volumes while the raw write is in progress,
    // the helper should also register a DADissenter for the disk. This temporarily blocks mount attempts from other processes,
    // ensuring an exclusive lock on the device during the critical write phase.
}

test "handle helper version check request" {
    const reportedVersion = handleHelperVersionCheckRequest();
    try std.testing.expectEqualSlices(u8, reportedVersion, env.HELPER_VERSION);
}
//
