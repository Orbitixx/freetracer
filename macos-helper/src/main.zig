const std = @import("std");
const env = @import("env.zig");
const fsops = @import("util/filesystem.zig");
const str = @import("util/strings.zig");
const testing = std.testing;
const freetracer_lib = @import("freetracer-lib");
const dev = freetracer_lib.device;
const fs = freetracer_lib.fs;

const ShutdownManager = @import("./managers/ShutdownManager.zig").ShutdownManagerSingleton;
const Debug = freetracer_lib.Debug;
const xpc = freetracer_lib.xpc;
const ISOParser = freetracer_lib.ISOParser;
const DeviceType = freetracer_lib.types.DeviceType;
const ImageType = freetracer_lib.types.ImageType;

const k = freetracer_lib.constants.k;
const c = freetracer_lib.c;
const String = freetracer_lib.String;
const Character = freetracer_lib.constants.Character;

const MachCommunicator = freetracer_lib.Mach.MachCommunicator;
const XPCService = freetracer_lib.Mach.XPCService;
const XPCConnection = freetracer_lib.Mach.XPCConnection;
const XPCObject = freetracer_lib.Mach.XPCObject;

const HelperRequestCode = freetracer_lib.constants.HelperRequestCode;
const HelperResponseCode = freetracer_lib.constants.HelperResponseCode;
const ReturnCode = freetracer_lib.constants.HelperReturnCode;
const WriteRequestData = freetracer_lib.constants.WriteRequestData;

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

// export var info_plist_data: [env.INFO_PLIST.len:0]u8 linksection("__TEXT,__info_plist") = env.INFO_PLIST.*;
// export var launchd_plist_data: [env.LAUNCHD_PLIST.len:0]u8 linksection("__TEXT,__launchd_plist") = env.LAUNCHD_PLIST.*;

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    // TODO: swap out debug allocator for production

    try Debug.init(allocator, .{});

    // Standard daemon out log does not support .DEBUG; .INFO and above only.
    Debug.log(.INFO, "------------------------------------------------------------------------------------------", .{});
    Debug.log(.INFO, "Debug logger is initialized.", .{});

    Debug.log(.INFO, "MAIN START - UID: {}, EUID: {}", .{ c.getuid(), c.geteuid() });

    // var args = std.process.args();
    // _ = args.next(); // skip program name
    //
    // if (args.next()) |arg| {
    //     const stdout = std.io.getStdOut().writer();
    //     try stdout.print("Received bsdName: {s}\n", .{arg});
    //
    //     const device = try dev.openDeviceValidated(arg);
    //     defer device.close();
    //
    //     try stdout.print("Completed test task!\n", .{});
    //
    //     return;
    // }

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

    // Terminate XPC connection and shutdown helper in case of null payload.
    if (message == null) {
        Debug.log(.ERROR, "XPC Server received a NULL request. Aborting processing response...", .{});
        ShutdownManager.terminateWithError(error.XPC_MESSAGE_PAYLOAD_NULL);
        return;
    }

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
        .WRITE_ISO_TO_DEVICE => processRequestWriteImage(connection, data),
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

fn respondWithErrorAndTerminate(
    err: struct { err: anyerror, message: []const u8 },
    response: struct { xpcConnection: XPCConnection, xpcResponseCode: HelperResponseCode },
) void {
    Debug.log(.ERROR, "{s} Error: {any}", .{ err.message, err.err });
    const xpcErrorResponse = XPCService.createResponse(response.xpcResponseCode);
    defer XPCService.releaseObject(xpcErrorResponse);
    XPCService.connectionSendMessage(response.xpcConnection, xpcErrorResponse);
    ShutdownManager.terminateWithError(err.err);
}

fn sendXPCReply(connection: XPCConnection, reply: HelperResponseCode, comptime logMessage: []const u8) void {
    Debug.log(.INFO, logMessage, .{});
    const replyObject = XPCService.createResponse(reply);
    XPCService.connectionSendMessage(connection, replyObject);
    XPCService.releaseObject(replyObject);
}

fn processRequestWriteImage(connection: XPCConnection, data: XPCObject) void {
    //
    const isoPath: []const u8 = XPCService.parseString(data, "isoPath");
    const deviceBsdName: []const u8 = XPCService.parseString(data, "disk");
    const deviceServiceId: c_uint = @intCast(XPCService.getUInt64(data, "deviceServiceId"));
    const deviceType: DeviceType = @enumFromInt(XPCService.getUInt64(data, "deviceType"));
    const imageType: ImageType = @enumFromInt(XPCService.getUInt64(data, "imageType"));

    defer XPCService.releaseObject(data);

    Debug.log(.INFO, "Recieved service: {d}", .{deviceServiceId});

    const userHomePath: []const u8 = XPCService.getUserHomePath(connection) catch |err| {
        respondWithErrorAndTerminate(
            .{ .err = err, .message = "Unable to retrieve user home path." },
            .{ .xpcConnection = connection, .xpcResponseCode = .ISO_WRITE_FAIL },
        );
        return;
    };

    const isoFile = fsops.openFileValidated(isoPath, .{ .userHomePath = userHomePath, .imageType = imageType }) catch |err| {
        respondWithErrorAndTerminate(
            .{ .err = err, .message = "Unable to open ISO file or its directory." },
            .{ .xpcConnection = connection, .xpcResponseCode = .ISO_FILE_INVALID },
        );
        return;
    };

    defer isoFile.close();

    sendXPCReply(connection, .ISO_FILE_VALID, "ISO File is determined to be valid and is successfully opened.");

    const device = dev.openDeviceValidated(deviceBsdName, deviceType) catch |err| {
        switch (err) {
            error.AccessDenied => {
                respondWithErrorAndTerminate(
                    .{ .err = err, .message = "Helper required disk access permissions." },
                    .{ .xpcConnection = connection, .xpcResponseCode = .NEED_DISK_PERMISSIONS },
                );
                return;
            },
            else => {
                respondWithErrorAndTerminate(
                    .{ .err = err, .message = "Unable to safely open specified device, validation error." },
                    .{ .xpcConnection = connection, .xpcResponseCode = .DEVICE_INVALID },
                );
                return;
            },
        }
    };

    defer device.close();

    sendXPCReply(connection, .DEVICE_VALID, "Device is determined to be valid and is successfully opened.");

    // const fd: c_int = @intCast(XPCService.getFileDescriptor(data, "fd"));
    // defer _ = c.close(fd);

    // const path = "/dev/disk5";
    // const fd: c_int = c.open(path, c.O_RDWR, @as(c_uint, 0o644));
    //
    // if (fd < 0) {
    //     Debug.log(.ERROR, "fd is -1 :(", .{});
    //     const err_num = c.__error().*;
    //     const err_str = c.strerror(err_num);
    //     Debug.log(.ERROR, "open() failed with errno {}: {s}", .{ err_num, err_str });
    //     respondWithErrorAndTerminate(
    //         .{ .err = error.fdIsNull, .message = "fd is -1." },
    //         .{ .xpcConnection = connection, .xpcResponseCode = .DEVICE_INVALID },
    //     );
    //     return;
    // }
    //
    // defer _ = c.close(fd);

    // if (true) {
    //     Debug.log(.INFO, "TEST SUCCESS", .{});
    //     return;
    // }

    // var sampleData: [81920]u8 = std.mem.zeroes([81920]u8);
    // @memset(sampleData[0..], 0xAA);
    //
    // const bytes_written = c.write(fd, sampleData[0..].ptr, @as(usize, @intCast(sampleData.len)));
    //
    // if (bytes_written < 0) {
    //     respondWithErrorAndTerminate(
    //         .{ .err = error.fdIsNull, .message = "fd is -1." },
    //         .{ .xpcConnection = connection, .xpcResponseCode = .ISO_WRITE_FAIL },
    //     );
    //     return;
    // }

    fsops.writeISO(connection, isoFile, device) catch |err| {
        respondWithErrorAndTerminate(
            .{ .err = err, .message = "Unable to write ISO to device." },
            .{ .xpcConnection = connection, .xpcResponseCode = .ISO_WRITE_FAIL },
        );
        return;
    };

    sendXPCReply(connection, .ISO_WRITE_SUCCESS, "ISO image successfully written to device!");

    fsops.verifyWrittenBytes(connection, isoFile, device) catch |err| {
        respondWithErrorAndTerminate(
            .{ .err = err, .message = "Unable to verify written ISO image." },
            .{ .xpcConnection = connection, .xpcResponseCode = .WRITE_VERIFICATION_FAIL },
        );
        return;
    };

    sendXPCReply(connection, .WRITE_VERIFICATION_SUCCESS, "Written ISO image successfully verified!");

    ShutdownManager.exitSuccessfully();

    // TODO:
    // To prevent the operating system from automatically remounting volumes while the raw write is in progress,
    // the helper should also register a DADissenter for the disk. This temporarily blocks mount attempts from other processes,
    // ensuring an exclusive lock on the device during the critical write phase.
}
