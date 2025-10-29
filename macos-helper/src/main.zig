//! # Freetracer Privileged Helper (SMJobBlessed)
//!
//! This module implements the entry point and XPC dispatch loop for the privileged helper,
//! which runs with elevated privileges (UID 0) to perform disk I/O and device management
//! operations that the unprivileged GUI cannot perform directly.
//!
//! ## Trust Model & Security Assumptions
//!
//! - **Caller Authentication:** XPC messages are authenticated against a known bundle ID and
//!   team ID (verified in `xpcRequestHandler` via `XPCService.authenticateMessage`).
//!   Only processes signed by the trusted team are allowed to call this helper.
//!
//! - **Implicit Trust Boundary:** Once authenticated, all HelperRequestCode operations are
//!   allowed without further per-operation ACL checks. Future deployments MUST add
//!   whitelist validation to prevent compromised GUI processes from invoking arbitrary
//!   operations. See SECURITY.md for hardening guidelines.
//!
//! - **Input Validation:** Core parameters (imagePath, deviceBsdName) are validated by
//!   `fs.openFileValidated()` and `dev.openDeviceValidated()`. Malformed XPC payloads
//!   are caught and propagated as errors; silent defaults MUST be avoided.
//!
//! ## Request/Response Contract
//!
//! Request codes are defined in `freetracer_lib.constants.HelperRequestCode`:
//!   - INITIAL_PING: Heartbeat; responds with INITIAL_PONG.
//!   - GET_HELPER_VERSION: Fetch helper version string; responds with HELPER_VERSION_OBTAINED.
//!   - WRITE_ISO_TO_DEVICE: Write ISO image to device with optional verification & eject.
//!
//! Response codes are defined in `freetracer_lib.constants.HelperResponseCode`:
//!   - ISO_FILE_VALID, DEVICE_VALID, ISO_WRITE_SUCCESS, etc. (see constants.zig)
//!
//! ## Lifecycle & Shutdown
//!
//! 1. `main()` initializes logging and XPC service.
//! 2. `xpcServer.start()` enters blocking dispatch loop (never returns in production).
//! 3. For each XPC message, `xpcRequestHandler()` is invoked by the dispatch queue.
//! 4. On error or completion, `ShutdownManager.terminateWithError()` or
//!    `ShutdownManager.exitSuccessfully()` schedules async exit via dispatch queue.
//!
//! ## Memory & Allocator
//!
//! All allocations use `DebugAllocator` for leak detection during development.
//! See line 70 TODO: Replace with production allocator (GeneralPurposeAllocator or page_allocator).
//!
// ========================================================================================
const std = @import("std");
const builtin = @import("builtin");
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

const meta = std.meta;

/// Validation errors for XPC request payloads.
/// These errors indicate semantic issues with request parameters (e.g., empty strings, invalid enums).
/// Unlike XPC protocol errors (null payload, auth failure), these result in a graceful error response
/// sent back to the caller via `respondWithErrorAndTerminate()`.
const RequestValidationError = error{
    /// ISO file path is empty or missing from XPC payload.
    EmptyIsoPath,
    /// Device identifier (bsdName) is empty or missing from XPC payload.
    EmptyDeviceIdentifier,
    /// Device type enum value is not a valid DeviceType variant.
    InvalidDeviceType,
    /// Image type enum value is not a valid ImageType variant.
    InvalidImageType,
};

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

/// Entry point for the SMJobBlessed privileged helper.
///
/// Initialization sequence:
/// 1. Creates a thread-safe DebugAllocator for memory leak detection.
/// 2. Initializes Debug logging system.
/// 3. Sets up XPC service listener with request handler callback.
/// 4. Registers with ShutdownManager for coordinated teardown.
/// 5. Enters XPC dispatch loop (blocking; never returns on success).
///
/// This function runs with elevated privileges (UID 0) because it is registered
/// as a privileged helper via launchd and SMJobBless. All XPC messages are
/// authenticated before processing.
///
/// Returns: Never in production (dispatch loop is blocking).
/// Errors: XPC setup failures, logging initialization failures.
pub fn main() !void {
    // var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    // const allocator = debugAllocator.allocator();

    var mainAllocator = switch (builtin.mode) {
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => std.heap.DebugAllocator(.{ .thread_safe = true }).init,
        else => std.heap.DebugAllocator(.{ .thread_safe = true }).init,
    };

    const allocator = mainAllocator.allocator();

    try Debug.init(allocator, .{});

    // Standard daemon out log does not support .DEBUG; .INFO and above only.
    Debug.log(.INFO, "------------------------------------------------------------------------------------------", .{});
    Debug.log(.INFO, "Debug logger is initialized.", .{});

    Debug.log(.INFO, "MAIN START - UID: {}, EUID: {}", .{ c.getuid(), c.geteuid() });

    var xpcServer = try XPCService.init(.{
        .isServer = true,
        .serviceName = "Freetracer Helper XPC Server",
        .serverBundleId = @ptrCast(env.BUNDLE_ID),
        .requestHandler = @ptrCast(&xpcRequestHandler),
    });

    // All deinit()'s are handled by the ShutdownManager because XPC's
    // main dispatch queue is thread-blocking and it never returns.
    ShutdownManager.init(&mainAllocator, &xpcServer);
    // Should never execute in production, but just in case as a safeguard.
    defer ShutdownManager.terminateWithError(error.HelperProcessUnexpectedlyTerminatedFromMain);

    // Thread-blocking queue dispatch; never returns -- must be forcefully interrupted.
    xpcServer.start();
}

/// C-convention callback invoked by libxpc when the helper receives a message on its Mach service.
///
/// Called for every inbound XPC message on the helper's Mach service.
/// Performs message authentication, type validation, and dispatch to the appropriate handler.
///
/// Preconditions:
///   - `connection`: Valid XPC connection handle from libxpc dispatch.
///   - `message`: XPC object (may be null if connection error).
///
/// Postconditions:
///   - On success: Response sent via XPCService.connectionSendMessage(); may call
///     ShutdownManager.terminateWithError() to exit.
///   - On error: Error logged; helper exits via ShutdownManager.
///
/// Note: This function runs in a dispatch queue thread context, so concurrent calls are possible.
/// Access to global state (ShutdownManager singleton) must be thread-safe.
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

/// Zig-native message processor; parses request code and dispatches to handler.
///
/// Called by `xpcRequestHandler` after XPC message authentication succeeds.
/// Extracts the HelperRequestCode enum from the XPC dictionary and routes to the appropriate
/// handler function (e.g., processInitialPing, processGetHelperVersion, processRequestWriteImage).
///
/// Error Handling:
///   - Parse failures (missing/invalid request code) are logged and ignored; the connection remains open.
///   - Handler errors (e.g., file I/O, device access) trigger respondWithErrorAndTerminate().
fn processRequestMessage(connection: XPCConnection, data: XPCObject) void {
    const request: HelperRequestCode = XPCService.parseRequest(data) catch |err| {
        Debug.log(.ERROR, "Helper failed to parse request, error: {any}", .{err});
        return;
    };

    Debug.log(.INFO, "Received request: {any}", .{request});

    switch (request) {
        .INITIAL_PING => processInitialPing(connection),
        .GET_HELPER_VERSION => processGetHelperVersion(connection),
        .UNMOUNT_DISK => Debug.log(.INFO, "Discrete unmount request received -- dropping request. Deprecated.", .{}),
        .WRITE_ISO_TO_DEVICE => processRequestWriteImage(connection, data) catch |err| {
            respondWithErrorAndTerminate(
                .{ .err = err, .message = "Helper failed to process the write image request" },
                .{ .xpcConnection = connection, .xpcResponseCode = .ISO_WRITE_FAIL },
            );
        },
    }
}

/// Handles INITIAL_PING request; sends back INITIAL_PONG as acknowledgment.
/// Used by GUI to verify helper is running and responsive.
fn processInitialPing(connection: XPCConnection) void {
    const reply: XPCObject = XPCService.createResponse(.INITIAL_PONG);
    defer XPCService.releaseObject(reply);
    XPCService.connectionSendMessage(connection, reply);
}

/// Handles GET_HELPER_VERSION request; sends back HELPER_VERSION_OBTAINED with version string.
/// Used by GUI to detect helper version and compatibility.
fn processGetHelperVersion(connection: XPCConnection) void {
    const reply: XPCObject = XPCService.createResponse(.HELPER_VERSION_OBTAINED);
    defer XPCService.releaseObject(reply);
    XPCService.createString(reply, "version", @ptrCast(env.HELPER_VERSION));
    XPCService.connectionSendMessage(connection, reply);
}

/// Sends error response to caller and schedules helper shutdown.
///
/// Logs the error with context, creates an XPC error response using the provided response code,
/// sends it back to the caller, and initiates graceful shutdown via ShutdownManager.
///
/// Postcondition: Helper will exit after flushing XPC message and cleanup is coordinated by
/// the dispatch queue through ShutdownManager.terminateWithError().
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

/// Convenience helper to emit a success response and keep logging consistent across request stages.
fn sendXPCReply(connection: XPCConnection, reply: HelperResponseCode, comptime logMessage: []const u8) void {
    Debug.log(.INFO, logMessage, .{});
    const replyObject = XPCService.createResponse(reply);
    XPCService.connectionSendMessage(connection, replyObject);
    XPCService.releaseObject(replyObject);
}

/// Handles WRITE_ISO_TO_DEVICE request: ISO image validation, device write, verification, and eject.
///
/// Request XPC Dict Parameters (from GUI):
///   - imagePath (string): Absolute path to ISO image file.
///   - disk (string): Device identifier (e.g., "disk2").
///   - deviceServiceId (uint64): Service ID of the device (for validation).
///   - deviceType (uint64): Device type enum (cast from DeviceType).
///   - config_userForced (uint64): If non-zero, skip image validation (user acknowledged warnings).
///   - config_ejectDevice (uint64): If non-zero, eject device after write.
///   - config_verifyBytes (uint64): If non-zero, verify all written bytes after write.
///
/// Sequence:
/// 1. Parse and validate XPC payload.
/// 2. Open and validate image image file.
/// 3. Open device (with permission error handling).
/// 4. Write image to device (with progress updates over XPC).
/// 5. Optionally verify written bytes.
/// 6. Optionally eject device.
/// 7. Exit helper on success or error.
fn processRequestWriteImage(connection: XPCConnection, data: XPCObject) !void {
    Debug.log(.INFO, "Parsing write request from XPC message...", .{});

    // Parse core identifiers and device metadata
    const imagePath: [:0]const u8 = try XPCService.parseString(data, "imagePath");
    const deviceBsdName: [:0]const u8 = try XPCService.parseString(data, "disk");
    const deviceServiceId: c_uint = @intCast(XPCService.getUInt64(data, "deviceServiceId") catch 0);

    if (deviceServiceId == 0) return error.FailedToParseDeviceServiceId;

    const deviceTypeInt: u64 = try XPCService.getUInt64(data, "deviceType");
    const deviceType = try meta.intToEnum(DeviceType, deviceTypeInt);

    // Parse consolidated configuration flags (non-critical; default to disabled on parse error)
    const configUserForced: u64 = XPCService.getUInt64(data, "config_userForced") catch 0;
    const configEjectDevice: u64 = XPCService.getUInt64(data, "config_ejectDevice") catch 0;
    const configVerifyBytes: u64 = XPCService.getUInt64(data, "config_verifyBytes") catch 0;

    Debug.log(.INFO, "Parsed write request: disk={s}, deviceServiceId={d}, config={{userForced={}, ejectDevice={}, verifyBytes={}}}", .{
        deviceBsdName,
        deviceServiceId,
        configUserForced != 0,
        configEjectDevice != 0,
        configVerifyBytes != 0,
    });

    // Validate core parameters
    if (imagePath.len == 0) return RequestValidationError.EmptyIsoPath;
    if (deviceBsdName.len == 0) return RequestValidationError.EmptyDeviceIdentifier;

    Debug.log(.INFO, "Received service: {d}", .{deviceServiceId});

    const userHomePath: []const u8 = try XPCService.getUserHomePath(connection);

    const imageFile = fs.openFileValidated(imagePath, .{ .userHomePath = userHomePath }) catch |err| {
        respondWithErrorAndTerminate(
            .{ .err = err, .message = "Unable to open the image file or its directory." },
            .{ .xpcConnection = connection, .xpcResponseCode = .ISO_FILE_INVALID },
        );
        return;
    };

    defer imageFile.close();

    const imageValidationResult = fs.validateImageFile(imageFile);

    if (!imageValidationResult.isValid and configUserForced == 0) {
        respondWithErrorAndTerminate(
            .{ .err = error.ImageValidationFailed, .message = "Failed to validate image and user did not force unknown image." },
            .{ .xpcConnection = connection, .xpcResponseCode = .IMAGE_STRUCTURE_UNRECOGNIZED },
        );
        return;
    }

    sendXPCReply(connection, .ISO_FILE_VALID, "Image file is determined to be valid and is successfully opened.");

    var deviceHandle = dev.openDeviceValidated(deviceBsdName, deviceType) catch |err| {
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

    errdefer deviceHandle.close();

    sendXPCReply(connection, .DEVICE_VALID, "Device is determined to be valid and is successfully opened.");

    // Write ISO image to device; progress updates sent over XPC connection.
    fsops.writeISO(connection, imageFile, deviceHandle) catch |err| {
        respondWithErrorAndTerminate(
            .{ .err = err, .message = "Unable to write image to device." },
            .{ .xpcConnection = connection, .xpcResponseCode = .ISO_WRITE_FAIL },
        );
        return;
    };

    sendXPCReply(connection, .ISO_WRITE_SUCCESS, "Image successfully written to device!");

    // Verification step: read back and compare every byte written (optional, config-driven).
    if (configVerifyBytes != 0) {
        fsops.verifyWrittenBytes(connection, imageFile, deviceHandle) catch |err| {
            respondWithErrorAndTerminate(
                .{ .err = err, .message = "Unable to verify the written image." },
                .{ .xpcConnection = connection, .xpcResponseCode = .WRITE_VERIFICATION_FAIL },
            );
            return;
        };

        sendXPCReply(connection, .WRITE_VERIFICATION_SUCCESS, "Written image bytes successfully verified!");
    } else {
        Debug.log(.INFO, "Verification skipped: config.verifyBytes flag is disabled.", .{});
    }

    // NOTE: Must close the handle first, otherwise eject will return DeviceBusy.
    deviceHandle.close();

    // Eject device step: optional, config-driven.
    if (configEjectDevice != 0) {
        dev.ejectDevice(&deviceHandle) catch |err| {
            respondWithErrorAndTerminate(
                .{ .err = err, .message = "Unable to eject device." },
                .{ .xpcConnection = connection, .xpcResponseCode = .DEVICE_EJECT_FAIL },
            );
            return;
        };
        Debug.log(.INFO, "Device ejected successfully.", .{});
        sendXPCReply(connection, .DEVICE_EJECT_SUCCESS, "Device successfully ejected!");
    } else {
        Debug.log(.INFO, "Device eject skipped: config.ejectDevice flag is disabled.", .{});
    }

    // Ensure that completion status is delivered and completion reports are not dropped from over-saturated XPC channel
    // No issues in testing, but leaving in for a good measure. This is an important step to communicate back.
    // TODO: use XPC API to ensure a handshake delivery
    for (0..3) |_| {
        sendXPCReply(connection, .DEVICE_FLASH_COMPLETE, "Successfully finished the flashing process. Sending a repeating message...");
        std.Thread.sleep(50_000_000); // 50 ms gap
    }

    Debug.log(.INFO, "Finished executing, now termining helper...", .{});

    ShutdownManager.exitSuccessfully();
}

// ========================================================================================
// TEST SUITE
// ========================================================================================

test "RequestValidationError error set is defined correctly" {
    // RequestValidationError should have 4 variants: EmptyIsoPath, EmptyDeviceIdentifier,
    // InvalidDeviceType, InvalidImageType. This test verifies the error set exists.
    const error_set_info = @typeInfo(RequestValidationError);
    try testing.expect(error_set_info == .error_set);
}

test "HELPER_VERSION environment variable is configured" {
    try testing.expect(env.HELPER_VERSION.len > 0);
}

test "authentication environment variables are configured" {
    try testing.expect(env.BUNDLE_ID.len > 0);
    try testing.expect(env.MAIN_APP_BUNDLE_ID.len > 0);
    try testing.expect(env.MAIN_APP_TEAM_ID.len > 0);
}

test "invalid device type enum returns error" {
    const invalid_type: u64 = 99999;
    const result = meta.intToEnum(DeviceType, invalid_type);

    try testing.expectError(error.InvalidEnumTag, result);
}

test "XPC module types are accessible" {
    _ = XPCService;
    _ = XPCConnection;
    _ = XPCObject;
}

test "DebugAllocator can be instantiated" {
    var debug_alloc = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    defer _ = debug_alloc.deinit();

    const alloc = debug_alloc.allocator();
    const slice = try alloc.alloc(u8, 10);
    defer alloc.free(slice);

    try testing.expect(slice.len == 10);
}
