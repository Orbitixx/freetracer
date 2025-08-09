const std = @import("std");
const env = @import("env.zig");
const testing = std.testing;
const freetracer_lib = @import("freetracer-lib");

const Debug = freetracer_lib.Debug;
const xpc = freetracer_lib.xpc;
const ISOParser = freetracer_lib.ISOParser;

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

const WRITE_BLOCK_SIZE = 4096;
const MAX_PATH_BYTES = std.fs.max_path_bytes;

const TERMINATION_CAUSE = enum(u8) {
    HELPER_SUCCESSFULLY_EXITED,

    XPC_CONNECTION_UNAUTHORIZED,
    XPC_MESSAGE_PAYLOAD_NULL,
    XPC_ERROR_RUNNING_MESSAGE_CALLBACK,
    XPC_UNKNOWN_ERROR_ON_CALLBACK,

    REQUEST_DISK_UNMOUNT_DISK_STRING_INVALID,
    REQUEST_DISK_UNMOUNT_FAILED_TO_UNMOUNT_DISK,
    REQUEST_DISK_UNMOUNT_FAILED_TO_CREATE_DA_DISK_SESSION,
    REQUEST_DISK_UNMOUNT_FAILED_TO_CREATE_DA_DISK_REF,
    REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_DISK_INFO_DICT_REF,
    REQUEST_DISK_UNMOUNT_UNMOUNT_REQUEST_ON_INTERNAL_DEVICE,
    REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY,

    REQUEST_ISO_WRITE_ISO_INVALID,
};

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

const TerminationParams: type = struct {
    isError: bool = true,
    cause: ?TERMINATION_CAUSE = null,
    err: ?anyerror = null,
};

fn exitFunction(context: ?*anyopaque) callconv(.c) void {
    _ = context;

    globalShutdownManager.xpcService.deinit();
    Debug.deinit();
    _ = globalShutdownManager.allocator.detectLeaks();
    _ = globalShutdownManager.allocator.deinit();

    std.process.exit(0);
}

fn terminateHelperProcess(params: TerminationParams) void {
    if (params.isError) Debug.log(
        .ERROR,
        "Helper terminated because of an error: {any} or {any}.",
        .{ params.cause.?, params.err.? },
    ) else Debug.log(
        .INFO,
        "Helper terminated with code: {any}.",
        .{params.cause.?},
    );

    xpc.dispatch_async_f(xpc.dispatch_get_main_queue(), null, &exitFunction);

    // std.process.exit(if (params.cause) |cause| @intFromEnum(cause) else 99);
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
        terminateHelperProcess(.{ .cause = .XPC_CONNECTION_UNAUTHORIZED });
        return;
    } else Debug.log(.INFO, "Successfully authenticated incoming message...", .{});

    if (message == null) {
        Debug.log(.ERROR, "XPC Server received a NULL request. Aborting processing response...", .{});
        terminateHelperProcess(.{ .cause = .XPC_MESSAGE_PAYLOAD_NULL });
        return;
    }

    const msg_type = xpc.xpc_get_type(message);

    if (msg_type == xpc.XPC_TYPE_DICTIONARY) {
        processRequestMessage(connection, message);
    } else if (msg_type == xpc.XPC_TYPE_ERROR) {
        Debug.log(.ERROR, "An error occurred attemting to run a message handler callback.", .{});
        terminateHelperProcess(.{ .cause = .XPC_ERROR_RUNNING_MESSAGE_CALLBACK });
    } else {
        Debug.log(.ERROR, "XPC Server received an unknown message type.", .{});
        terminateHelperProcess(.{ .cause = .XPC_UNKNOWN_ERROR_ON_CALLBACK });
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

fn attemptDiskUnmount(connection: XPCConnection, data: XPCObject) bool {
    const disk: []const u8 = XPCService.parseString(data, "disk");

    if (!isDiskStringValid(disk)) {
        Debug.log(.ERROR, "Received/parsed disk string is invalid: {s}. Aborting processing request...", .{disk});
        terminateHelperProcess(.{ .cause = .REQUEST_DISK_UNMOUNT_DISK_STRING_INVALID });
        return false;
    }

    const result = requestUnmountWithIORegistry(disk);

    var response: XPCObject = undefined;

    if (result != .SUCCESS) {
        Debug.log(.ERROR, "Failed to unmount specified disk, error code: {any}", .{result});
        response = XPCService.createResponse(.DISK_UNMOUNT_FAIL);
        terminateHelperProcess(.{ .cause = .REQUEST_DISK_UNMOUNT_FAILED_TO_UNMOUNT_DISK });
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
        terminateHelperProcess(.{ .err = err });
        return;
    };

    const isoFile = openFileValidated(isoPath, .{ .userHomePath = userHomePath }) catch |err| {
        Debug.log(.ERROR, "Unable to safely open provided ISO file path: {s}, validation error: {any}", .{ isoPath, err });
        const xpcErrorResponse = XPCService.createResponse(.ISO_FILE_INVALID);
        defer XPCService.releaseObject(xpcErrorResponse);
        XPCService.connectionSendMessage(connection, xpcErrorResponse);
        terminateHelperProcess(.{ .err = err });
        return;
    };

    defer isoFile.close();

    Debug.log(.INFO, "ISO File is determined to be valid.", .{});
    const xpcReply: XPCObject = XPCService.createResponse(.ISO_FILE_VALID);
    defer XPCService.releaseObject(xpcReply);
    XPCService.connectionSendMessage(connection, xpcReply);

    const device = openDeviceValidated(deviceBsdName) catch |err| {
        // TODO: sanitize device name before logging
        Debug.log(.ERROR, "Unable to safely open device: {s}, validation error: {any}", .{ deviceBsdName, err });
        const xpcErrorResponse = XPCService.createResponse(.DEVICE_INVALID);
        defer XPCService.releaseObject(xpcErrorResponse);
        XPCService.connectionSendMessage(connection, xpcErrorResponse);
        terminateHelperProcess(.{ .err = err });
        return;
    };

    defer device.close();

    writeISO(connection, isoFile, device) catch |err| {
        Debug.log(.ERROR, "Unable to safely open provided ISO file path: {s}, validation error: {any}", .{ isoPath, err });
        const xpcErrorResponse = XPCService.createResponse(.ISO_FILE_INVALID);
        defer XPCService.releaseObject(xpcErrorResponse);
        XPCService.connectionSendMessage(connection, xpcErrorResponse);
        terminateHelperProcess(.{ .err = err });
        return;
    };

    terminateHelperProcess(.{ .isError = false, .cause = .HELPER_SUCCESSFULLY_EXITED });

    // TODO:
    // To prevent the operating system from automatically remounting volumes while the raw write is in progress,
    // the helper should also register a DADissenter for the disk. This temporarily blocks mount attempts from other processes,
    // ensuring an exclusive lock on the device during the critical write phase.
}

// Security caveat: ensure the received string is like "disk" or "rdisk"
fn isDiskStringValid(disk: []const u8) bool {

    // Ensure the length fits "diskX" at the very least (5 characters)
    std.debug.assert(disk.len >= 5);

    const isRawDisk: bool = std.mem.eql(u8, disk[0..5], "rdisk");

    // Capture the "disk" portion of "diskX"
    const isPrefixValid: bool = std.mem.eql(u8, disk[0..4], "disk") or std.mem.eql(u8, disk[0..5], "rdisk");

    Debug.log(.INFO, "disk[0..4]: {s}, disk[0..5]: {s}", .{ disk[0..4], disk[0..5] });

    // Capture the "X" portion of "diskX"
    const suffix: u8 = std.fmt.parseInt(u8, if (isRawDisk) disk[5..disk.len] else disk[4..disk.len], 10) catch |err| blk: {
        Debug.log(.ERROR, "isDiskStringValid(): unable to parse disk suffix, value: {s}. Error: {any}.", .{ disk, err });
        break :blk 0;
    };

    // Check if disk number is more than 1 (internal SSD) and under some unlikely arbitrary number like 100
    const isSuffixValid: bool = suffix > 1 and suffix < 100;

    return isPrefixValid and isSuffixValid;
}

const GlobalShutdownManager = struct {
    allocator: *std.heap.DebugAllocator(.{ .thread_safe = true }) = undefined,
    xpcService: *XPCService = undefined,
};

var globalShutdownManager: GlobalShutdownManager = .{};

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    //TODO: swap out debug allocator

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

    globalShutdownManager = .{
        .allocator = &debugAllocator,
        .xpcService = &xpcServer,
    };

    xpcServer.start();

    // TODO:The launchd.plist should be configured for on-demand launch, and the tool should exit after completing its work.
    Debug.log(.INFO, "Helper tool successfully terminated.", .{});
}

fn handleHelperVersionCheckRequest() [:0]const u8 {
    return env.HELPER_VERSION;
}

fn requestUnmountWithIORegistry(targetDisk: []const u8) ReturnCode {

    // TODO: perform a check to ensure the device has a kIOMediaRemovableKey key
    // TODO: refactor code to smalelr functions

    if (targetDisk.len < 2) return ReturnCode.MALFORMED_TARGET_DISK_STRING;

    Debug.log(.INFO, "Received bsdName: {s}", .{targetDisk});

    const bsdName = std.mem.sliceTo(targetDisk, 0x00);

    Debug.log(.INFO, "Sliced bsdName: {s}", .{bsdName});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) {
        Debug.log(.ERROR, "Failed to create DASession\n", .{});
        terminateHelperProcess(.{ .cause = .REQUEST_DISK_UNMOUNT_FAILED_TO_CREATE_DA_DISK_SESSION });
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
        terminateHelperProcess(.{ .cause = .REQUEST_DISK_UNMOUNT_FAILED_TO_CREATE_DA_DISK_REF });
        return ReturnCode.FAILED_TO_CREATE_DA_DISK_REF;
    }
    defer _ = c.CFRelease(daDiskRef);

    Debug.log(.INFO, "DA Disk refererence is successfuly created for the provided device BSD name.", .{});

    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));

    if (diskInfo == null) {
        terminateHelperProcess(.{ .cause = .REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_DISK_INFO_DICT_REF });
        return ReturnCode.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    }
    defer _ = c.CFRelease(diskInfo);

    Debug.log(.INFO, "DA Disk Description is successfully obtained/copied.", .{});

    // _ = c.CFShow(diskInfo);

    if (isTargetDiskInternalDevice(diskInfo)) {
        Debug.log(.ERROR, "ERROR: internal device detected on disk: {s}. Aborting unmount operations for device.", .{bsdName});
        terminateHelperProcess(.{ .cause = .REQUEST_DISK_UNMOUNT_UNMOUNT_REQUEST_ON_INTERNAL_DEVICE });
        return ReturnCode.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;
    }

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, null);

    c.CFRunLoopRun();

    return ReturnCode.SUCCESS;
}

fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    _ = context;

    Debug.log(.INFO, "Processing unmountDiskCallback()...", .{});

    const bsdNameCPtr: [*c]const u8 = c.DADiskGetBSDName(disk);
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

        Debug.log(.INFO, "Finished unmounting all volumes for device.", .{});

        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}

fn isTargetDiskInternalDevice(diskDictionaryRef: c.CFDictionaryRef) bool {
    const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskDictionaryRef, c.kDADiskDescriptionDeviceInternalKey));

    if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
        Debug.log(.ERROR, "Failed to obtain internal device key boolean.", .{});
        terminateHelperProcess(.{ .cause = .REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY });
        return true;
    }

    const isDeviceInternal: bool = (isInternalDeviceRef == c.kCFBooleanTrue);

    Debug.log(.INFO, "Finished checking for an internal device... isDeviceInternal: {any}", .{isDeviceInternal});

    return isDeviceInternal;
}

fn isFilePathAllowed(userHomePath: []const u8, pathString: []const u8) bool {
    var realPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

    // TODO: add other allowed paths
    const allowedPathsRelative = [_][]u8{
        @ptrCast(@constCast("/Desktop/")),
        @ptrCast(@constCast("/Documents/")),
        @ptrCast(@constCast("/Downloads/")),
    };

    var allowedPaths = std.mem.zeroes([allowedPathsRelative.len][std.fs.max_path_bytes]u8);

    for (allowedPathsRelative, 0..allowedPathsRelative.len) |pathRel, i| {
        @memcpy(allowedPaths[i][0..userHomePath.len], userHomePath);
        @memcpy(allowedPaths[i][userHomePath.len .. userHomePath.len + pathRel.len], pathRel);
    }

    for (allowedPaths) |allowedPath| {

        // Buffer overflow protection
        if (pathString.len > MAX_PATH_BYTES) {
            Debug.log(.ERROR, "isFilePathAllowed: Provided ISO path is too long (over MAX_PATH_BYTES).", .{});
            return false;
        }

        // Canonicalize the path string
        const realAllowedPath = std.fs.realpath(std.mem.sliceTo(&allowedPath, Character.NULL), &realPathBuffer) catch |err| {
            Debug.log(.ERROR, "isFilePathAllowed: Unable to resolve the real path of the allowed path. Error: {any}", .{err});
            return false;
        };

        if (std.mem.startsWith(u8, pathString, realAllowedPath)) return true;
    }

    return false;
}

fn unwrapUserHomePath(buffer: *[std.fs.max_path_bytes]u8, restOfPath: []const u8) ![]u8 {
    const userDir = std.posix.getenv("HOME") orelse return error.HomeEnvironmentVariableIsNULL;

    @memcpy(buffer[0..userDir.len], userDir);
    @memcpy(buffer[userDir.len .. userDir.len + restOfPath.len], restOfPath);

    return buffer[0 .. userDir.len + restOfPath.len];
}

fn openFileValidated(unsanitizedIsoPath: []const u8, params: struct { userHomePath: []const u8 }) !std.fs.File {

    // Buffer overflow protection
    if (unsanitizedIsoPath.len > MAX_PATH_BYTES) {
        Debug.log(.ERROR, "Provided ISO path is too long (over MAX_PATH_BYTES).", .{});
        return error.ISOFilePathTooLong;
    }

    if (params.userHomePath.len < 3) return error.UserHomePathTooShort;

    var realPathBuffer: [MAX_PATH_BYTES]u8 = std.mem.zeroes([MAX_PATH_BYTES]u8);
    var sanitizeStringBuffer: [MAX_PATH_BYTES]u8 = std.mem.zeroes([MAX_PATH_BYTES]u8);

    const isoPath = std.fs.realpath(unsanitizedIsoPath, &realPathBuffer) catch |err| {
        Debug.log(.ERROR, "Unable to resolve the real path of the povided ISO path: {s}. Error: {any}", .{
            String.sanitizeString(&sanitizeStringBuffer, unsanitizedIsoPath),
            err,
        });
        return error.UnableToResolveRealISOPath;
    };

    const printableIsoPath = String.sanitizeString(&sanitizeStringBuffer, isoPath);

    if (isoPath.len < 8) {
        Debug.log(.ERROR, "Provided ISO path is less than 8 characters long. Likely invalid, aborting for safety...", .{});
        return error.ISOFilePathTooShort;
    }

    const directory = std.fs.path.dirname(isoPath) orelse ".";
    const fileName = std.fs.path.basename(isoPath);

    if (!isFilePathAllowed(params.userHomePath, directory)) {
        Debug.log(.ERROR, "Provided ISO contains a disallowed path: {s}", .{printableIsoPath});
        return error.ISOFileContainsRestrictedPaths;
    }

    const dir = std.fs.openDirAbsolute(directory, .{ .no_follow = true }) catch |err| {
        Debug.log(.ERROR, "Unable to open the directory of specified ISO file. Aborting... Error: {any}", .{err});
        return error.UnableToOpenDirectoryOfSpecificedISOFile;
    };

    const isoFile = dir.openFile(fileName, .{ .mode = .read_only, .lock = .exclusive }) catch |err| {
        Debug.log(.ERROR, "Failed to open ISO file or obtain an exclusive lock. Error: {any}", .{err});
        return error.UnableToOpenISOFileOrObtainExclusiveLock;
    };

    const fileStat = isoFile.stat() catch |err| {
        Debug.log(.ERROR, "Failed to obtain ISO file stat. Error: {any}", .{err});
        return error.UnableToObtainISOFileStat;
    };

    if (fileStat.kind != std.fs.File.Kind.file) {
        Debug.log(
            .ERROR,
            "The provided ISO path is not a recognized file by file system. Symlinks and other kinds are not allowed. Kind used: {any}",
            .{fileStat.kind},
        );
        return error.InvalidISOFileKind;
    }

    // Minimum ISO system block: 16 sectors by 2048 bytes each + 1 sector for PVD contents.
    if (fileStat.size < 16 * 2048 + 1) return error.InvalidISOSystemStructure;

    const isoValidationResult = ISOParser.validateISOFileStructure(isoFile);

    if (isoValidationResult != .ISO_VALID) {
        Debug.log(.ERROR, "Invalid ISO file structure detected. Aborting... Error code: {any}", .{isoValidationResult});
        return error.InvalidISOStructureDoesNotConformToISO9660;
    }

    return isoFile;
}

fn openDeviceValidated(bsdName: []const u8) !std.fs.File {
    if (bsdName.len < 2) return error.DeviceNameTooShort;
    if (bsdName.len > std.fs.max_name_bytes) return error.DeviceNameTooLong;

    const deviceDir = "/dev/";

    // Accept flat filename only (i.e. same level as directory)
    if (std.mem.count(u8, bsdName, "/") > 0) return error.DeviceBSDNameIsNotAFlatFilename;

    // Replace non-printable characters in the BSD name
    var sanitizedBuffer: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);
    const sanitizedBsdName = String.sanitizeString(&sanitizedBuffer, bsdName);

    // This performs a check via Disk Arbitration on whether or not the device is internal or removable
    const unmountResult = requestUnmountWithIORegistry(sanitizedBsdName);
    if (unmountResult != .SUCCESS) return error.UnableToUnmountDevice;

    // Open directory without following symlinks
    const directory = try std.fs.openDirAbsolute(deviceDir, .{ .no_follow = true });

    // Open device and ensure it's a block device and not a character device or another kind
    const device = try directory.openFile(sanitizedBsdName, .{ .mode = .read_write, .lock = .exclusive });
    errdefer device.close();
    const deviceStat = try device.stat();
    if (deviceStat.kind != std.fs.File.Kind.block_device) return error.FileIsNotABlockDevice;

    // Ensure device is not the same as the "/" root filesystem
    const rootFs = try std.fs.openFileAbsolute("/", .{ .lock = .none, .mode = .read_only });
    defer rootFs.close();
    const rootFsStat = try rootFs.stat();

    if (deviceStat.inode == rootFsStat.inode) return error.DeviceCannotBeActiveRootFileSystem;

    return device;
}

fn writeISO(connection: XPCConnection, isoFile: std.fs.File, device: std.fs.File) !void {
    Debug.log(.DEBUG, "Begin writing prep...", .{});
    var writeBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const fileStat = try isoFile.stat();
    const ISO_SIZE = fileStat.size;

    var currentByte: u64 = 0;
    var previousProgress: i64 = 0;
    var currentProgress: i64 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{ISO_SIZE});
    Debug.log(.INFO, "Writing ISO to device, please wait...", .{});

    while (currentByte < ISO_SIZE) {
        previousProgress = currentProgress;

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
        currentProgress = @as(i64, @intCast((currentByte * 100) / ISO_SIZE));

        // Only send an XPC message if the progress moved at least 1%
        if (currentProgress - previousProgress < 1) continue;

        const progressUpdate = XPCService.createResponse(.ISO_WRITE_PROGRESS);
        defer XPCService.releaseObject(progressUpdate);
        XPCService.createInt64(progressUpdate, "write_progress", currentProgress);
        XPCService.connectionSendMessage(connection, progressUpdate);
    }

    try device.sync();

    Debug.log(.INFO, "Finished writing ISO image to device!", .{});
}

test "handle helper version check request" {
    const reportedVersion = handleHelperVersionCheckRequest();
    try std.testing.expectEqualSlices(u8, reportedVersion, env.HELPER_VERSION);
}

test "unwrapping user home path generates a correct path" {
    var buffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
    const expectedOutput = std.posix.getenv("HOME");
    try std.testing.expect(expectedOutput != null);

    const result: [:0]const u8 = @ptrCast(try unwrapUserHomePath(&buffer, ""));
    try std.testing.expect(std.mem.eql(u8, expectedOutput.?, result));
}

test "selecting an ISO in Documents folder is allowed" {
    var buffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
    const userHomePath = std.posix.getenv("HOME") orelse return error.UserHomePathIsNULL;
    const path = try unwrapUserHomePath(&buffer, env.TEST_ISO_FILE_PATH);
    try std.testing.expect(isFilePathAllowed(userHomePath, path) == true);
}

test "selecting an file in other directories is disallowed" {
    var buffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

    const userHomePath = std.posix.getenv("HOME") orelse return error.UserHomePathIsNULL;

    const path1: []const u8 = "/etc/sudoers";
    try std.testing.expect(isFilePathAllowed(userHomePath, path1) == false);

    const path2: []const u8 = "/dev/zero";
    try std.testing.expect(isFilePathAllowed(userHomePath, path2) == false);

    const path3: []const u8 = "/Library/LaunchDaemons/";
    try std.testing.expect(isFilePathAllowed(userHomePath, path3) == false);

    const path4: []const u8 = try unwrapUserHomePath(&buffer, "/Applications/");
    try std.testing.expect(isFilePathAllowed(userHomePath, path4) == false);

    const path5: []const u8 = try unwrapUserHomePath(&buffer, "/Notes/");
    try std.testing.expect(isFilePathAllowed(userHomePath, path5) == false);
}

test "calling openFileValidated returns a valid file handle" {
    const isoFile = try openFileValidated(
        // Simulated; during runtime, provided by the XPC client.
        env.USER_HOME_PATH ++ env.TEST_ISO_FILE_PATH,
        // Simulated; during runtime, provided securily by XPCService.getUserHomePath()
        .{ .userHomePath = std.posix.getenv("HOME") orelse return error.UserHomePathIsNULL },
    );

    defer isoFile.close();

    try std.testing.expect(@TypeOf(isoFile) == std.fs.File);
}
