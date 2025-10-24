// Safe wrappers around Apple's XPC API and related security utilities used by
// the GUI and privileged helper to exchange messages over the blessed Mach
// service. Provides helpers for connection lifecycle, request/response
// serialization, and code-signing validation of clients.
// ---------------------------------------------------------------------------
const std = @import("std");
const builtin = @import("builtin");
const k = @import("../constants.zig").k;
const c = @import("../types.zig").c;
const Debug = @import("../util/debug.zig");
const isMacOS = @import("../types.zig").isMacOS;

const xpc = @cImport(@cInclude("xpc_helper.h"));

pub const XPCConnection = xpc.xpc_connection_t;
pub const XPCDispatchQueue = xpc.dispatch_queue_t;
pub const XPCObject = xpc.xpc_object_t;

const Constants = @import("../constants.zig");

const HelperRequestCode = Constants.HelperRequestCode;
const HelperResponseCode = Constants.HelperResponseCode;
const Character = Constants.Character;

const NullTerminatedStringType: type = [:0]const u8;

const XPCRequestHandler = *const fn (connection: xpc.xpc_connection_t, message: xpc.xpc_object_t) callconv(.c) void;

const XPCServiceConfig = struct {
    isServer: bool = false,
    serverBundleId: [:0]const u8,
    clientBundleId: [:0]const u8 = undefined,
    serviceName: []const u8,
    requestHandler: XPCRequestHandler,
};

pub const DictionaryError = error{
    MissingKey,
    UnexpectedType,
    NullString,
};

const XPCRequestTimer = struct {
    timeOfLastRequest: i64 = 0,
    isTimerSet: bool = false,

    pub fn start(self: *XPCRequestTimer) void {
        self.timeOfLastRequest = std.time.timestamp();
        self.isTimerSet = true;
    }

    pub fn reset(self: *XPCRequestTimer) void {
        self.timeOfLastRequest = 0;
        self.isTimerSet = false;
    }
};

pub const XPCService = struct {
    service: XPCConnection = undefined,
    clientDispatchQueue: XPCDispatchQueue = undefined,
    config: XPCServiceConfig,
    timer: XPCRequestTimer = .{},

    const Self = @This();

    /// Creates a service wrapper but does not establish the Mach connection yet.
    pub fn init(config: XPCServiceConfig) !Self {
        Debug.log(.INFO, "{s}: Initializing XPC Service...", .{config.serviceName});

        if (!config.isServer and config.clientBundleId.len < 1) return error.ClientMustSpecifyCliendBundleIdInXPCConfig;

        return Self{
            .config = config,
        };
    }

    /// Binds to the Mach service and, for clients, performs an initial ping.
    pub fn start(self: *Self) void {
        self.service = xpc.xpc_connection_create_mach_service(
            @ptrCast(self.config.serverBundleId),
            if (self.config.isServer) xpc.dispatch_get_main_queue() else null,
            if (self.config.isServer) xpc.XPC_CONNECTION_MACH_SERVICE_LISTENER else xpc.XPC_CONNECTION_MACH_SERVICE_PRIVILEGED,
        );

        if (self.service == null) {
            Debug.log(.ERROR, "{s}: Unable to create a mach service. Aborting...", .{self.config.serviceName});
            return;
        }

        // TODO: within the connection event handler -- interrogate the client and its identity
        // use Security framework (such as SecCodeCopyGuestWithAttributes and SecCodeCheckValidity) to evaluate
        // the code signature of the client associated with the audit token
        // verify developer id AND bundle identifier associated with the token
        xpc.XPCConnectionSetEventHandler(self.service, @ptrCast(&connectionHandler), @ptrCast(self.config.requestHandler));

        if (!self.config.isServer) {
            xpc.XPCMessageSetEventHandler(self.service, @ptrCast(self.config.requestHandler));
            self.clientDispatchQueue = xpc.dispatch_queue_create(@ptrCast(self.config.clientBundleId), null);
            xpc.xpc_connection_set_target_queue(self.service, self.clientDispatchQueue);
        }

        xpc.xpc_connection_resume(self.service);

        Debug.log(.INFO, "{s}: Service started, listening for connections...", .{self.config.serviceName});

        if (self.config.isServer) xpc.dispatch_main() else {
            // Allow a small gap of time for XPC service to spin up (100ms)
            std.Thread.sleep(100_000_000);
            self.timer.start();
            pingServer(self.service);
        }
    }

    /// Event handler registered for listener sockets; attaches the dictionary
    /// handler to newly accepted client connections.
    pub fn connectionHandler(connection: xpc.xpc_connection_t, msgHandler: xpc.XPCMessageHandler) callconv(.c) void {
        const connectionType = xpc.xpc_get_type(connection);

        if (connectionType == xpc.XPC_TYPE_CONNECTION) {
            Debug.log(.INFO, "New XPC connection established", .{});
            xpc.XPCMessageSetEventHandler(connection, msgHandler);
            xpc.xpc_connection_resume(connection);
        }
    }

    /// Sends provided dictionary synchronously (on XPC thread) via MacOS' XPC bridge.
    pub fn connectionSendMessage(connection: XPCConnection, dataDictionary: XPCObject) void {
        xpc.xpc_connection_send_message(connection, dataDictionary);
    }

    /// Returns the authenticated user's home directory derived from the XPC
    /// audit token. Rejects root callers and missing passwd entries.
    pub fn getUserHomePath(connection: XPCConnection) ![]const u8 {
        const euid: c_uint = c.xpc_connection_get_euid(@ptrCast(connection));
        if (euid == 0) return error.ClientApplicationIsRunningAsRootIsDisallowedBySecurityPolicy;

        const userEntry = c.getpwuid(euid);
        if (userEntry == null) return error.UnableToMapUserToEUID;

        if (userEntry.*.pw_dir == null) return error.UnableToMapUserHomeDirectory;

        return std.mem.span(userEntry.*.pw_dir);
    }

    /// Validates the sender's code signature by comparing bundle and team IDs.
    pub fn authenticateMessage(message: XPCObject, authenticClientBundleId: [:0]const u8, authenticClientTeamId: [:0]const u8) bool {
        var secCodeRef: c.SecCodeRef = null;

        var operationStatus: c.OSStatus = c.SecCodeCreateWithXPCMessage(message, c.kSecCSDefaultFlags, &secCodeRef);

        if (operationStatus != c.errSecSuccess or secCodeRef == null) {
            Debug.log(.ERROR, "Failed to obtain security code reference to running code. Invalidating message...", .{});
            return false;
        }

        defer c.CFRelease(secCodeRef);

        operationStatus = c.SecCodeCheckValidity(secCodeRef, c.kSecCSDefaultFlags, null);

        if (operationStatus != c.errSecSuccess) {
            Debug.log(.ERROR, "Failed to verify the validity of the requester's code signature. Invalidating message...", .{});
            return false;
        }

        var codeSigningInfo: c.CFDictionaryRef = null;

        operationStatus = c.SecCodeCopySigningInformation(secCodeRef, c.kSecCSSigningInformation, &codeSigningInfo);

        if (operationStatus != c.errSecSuccess or codeSigningInfo == null) {
            Debug.log(.ERROR, "Failed to obtain code signing information. Invalidating message...", .{});
            return false;
        }

        defer c.CFRelease(codeSigningInfo);

        const isValidBundleId = validateDictionaryString(codeSigningInfo, c.kSecCodeInfoIdentifier, authenticClientBundleId);
        const isValidTeamId = validateDictionaryString(codeSigningInfo, c.kSecCodeInfoTeamIdentifier, authenticClientTeamId);

        return isValidBundleId and isValidTeamId;
    }

    pub fn deinit(self: *Self) void {
        if (self.service != null) {
            xpc.xpc_connection_cancel(self.service);
            xpc.xpc_release(self.service);
            self.service = null;
        }
    }

    pub fn pingServer(connection: XPCConnection) void {
        Debug.log(.INFO, "Sending initial ping to the Helper. Awaiting response...", .{});
        const ping = createRequest(.INITIAL_PING);
        defer releaseObject(ping);
        connectionSendMessage(connection, ping);
    }

    pub fn createRequest(value: HelperRequestCode) XPCObject {
        const dict: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
        xpc.xpc_dictionary_set_int64(dict, "request", @intFromEnum(value));
        return dict;
    }

    pub fn parseRequest(dict: XPCObject) DictionaryError!HelperRequestCode {
        const raw = try getInt64(dict, "request");
        return @enumFromInt(raw);
    }

    pub fn createResponse(value: HelperResponseCode) XPCObject {
        const dict: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
        xpc.xpc_dictionary_set_int64(dict, "response", @intFromEnum(value));
        return dict;
    }

    pub fn parseResponse(dict: XPCObject) DictionaryError!HelperResponseCode {
        const raw = try getInt64(dict, "response");
        return @enumFromInt(raw);
    }

    pub fn createString(dict: XPCObject, key: [:0]const u8, value: [:0]const u8) void {
        xpc.xpc_dictionary_set_string(dict, @ptrCast(key), @ptrCast(value));
    }

    pub fn parseString(dict: XPCObject, key: [:0]const u8) DictionaryError![:0]const u8 {
        _ = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_STRING);
        const c_str = xpc.xpc_dictionary_get_string(dict, @ptrCast(key));
        if (c_str == null) return DictionaryError.NullString;
        const ptr: [*:0]const u8 = @ptrCast(c_str);
        return std.mem.span(ptr);
    }

    pub fn createInt64(dict: XPCObject, key: [:0]const u8, value: i64) void {
        xpc.xpc_dictionary_set_int64(dict, @ptrCast(key), value);
    }

    pub fn getInt64(dict: XPCObject, key: [:0]const u8) DictionaryError!i64 {
        _ = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_INT64);
        return xpc.xpc_dictionary_get_int64(dict, @ptrCast(key));
    }

    pub fn createUInt64(dict: XPCObject, key: [:0]const u8, value: u64) void {
        xpc.xpc_dictionary_set_uint64(dict, @ptrCast(key), value);
    }

    pub fn getUInt64(dict: XPCObject, key: [:0]const u8) DictionaryError!u64 {
        _ = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_UINT64);
        return xpc.xpc_dictionary_get_uint64(dict, @ptrCast(key));
    }

    pub fn createFileDescriptor(dict: XPCObject, key: [:0]const u8, value: c_int) void {
        const fdObj: XPCObject = xpc.xpc_fd_create(value);
        if (fdObj == null) return;
        xpc.xpc_dictionary_set_value(dict, @ptrCast(key), fdObj);
        xpc.xpc_release(fdObj);
    }

    pub fn getFileDescriptor(dict: XPCObject, key: [:0]const u8) DictionaryError!c_int {
        const value = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_FD);
        // xpc_dictionary_dup_fd performs the type check but returns -1 on failure.
        const fd = xpc.xpc_dictionary_dup_fd(dict, @ptrCast(key));
        if (fd == -1) return DictionaryError.UnexpectedType;
        _ = value; // already retained by dup_fd
        return fd;
    }

    pub fn releaseObject(obj: XPCObject) void {
        xpc.xpc_release(obj);
    }

    pub fn connectionFlush(connection: XPCConnection) void {
        xpc.XPCConnectionFlush(connection);
    }
};

// Ensures a value exists in the dicrionary, it is not null and is of the expected type
fn requireDictionaryValue(dict: XPCObject, key: [:0]const u8, comptime expectedType: xpc.xpc_type_t) DictionaryError!XPCObject {
    const value = xpc.xpc_dictionary_get_value(dict, @ptrCast(key));
    if (value == null) return DictionaryError.MissingKey;

    const value_type = xpc.xpc_get_type(value);
    if (value_type != expectedType) return DictionaryError.UnexpectedType;

    return value;
}

fn validateDictionaryString(dictionary: c.CFDictionaryRef, key: c.CFStringRef, validString: [:0]const u8) bool {
    const stringBuffer = getStringFromDictionary(dictionary, key) catch |err| {
        if (err == error.UnableToRetrieveStringFromRef) Debug.log(.ERROR, "Unable to retreive string from Ref... Expected: '{s}'. Error: {any}", .{ validString, err });
        return false;
    };

    const finalString: [:0]const u8 = @ptrCast(std.mem.sliceTo(&stringBuffer, Character.NULL));

    // Debug.log(.INFO, "validateDictionaryString(): Expected '{s}', retreived: '{s}'.", .{ validString, finalString });

    return std.mem.eql(u8, finalString, validString);
}

fn getStringFromDictionary(dictionary: c.CFDictionaryRef, key: c.CFStringRef) ![512]u8 {
    // Pre-allocate a large enough buffer to avoid stack overflow vector of attack
    var resultBuffer: [512]u8 = std.mem.zeroes([512]u8);

    const resultValueRef_opt = c.CFDictionaryGetValue(dictionary, key);

    if (resultValueRef_opt == null) return error.UnableToRetrieveStringFromRef;

    const resultValueRef: c.CFStringRef = @ptrCast(resultValueRef_opt);
    const stringParsingResult: c.Boolean = c.CFStringGetCString(resultValueRef, &resultBuffer, resultBuffer.len, c.kCFStringEncodingUTF8);

    if (stringParsingResult != c.TRUE) {
        return error.UnableToRetrieveStringFromRef;
    }

    const effectiveLen = std.mem.indexOfScalar(u8, &resultBuffer, Character.NULL) orelse resultBuffer.len;

    if (effectiveLen < 2) {
        Debug.log(.ERROR, "Retrieved string is too short to be meaningful: '{s}'.", .{std.mem.sliceTo(&resultBuffer, Character.NULL)});
        return error.StringIsTooShortToBeMeaningful;
    }

    return resultBuffer;
}
