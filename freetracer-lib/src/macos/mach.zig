//! Mach and XPC Framework Interface
//!
//! Provides safe, high-level wrappers around macOS XPC (inter-process communication)
//! and related Security framework APIs. Enables inter-process communication
//! between the GUI application and the privileged helper process.
//!
//! Key Responsibilities:
//! - XPC connection lifecycle management (create, resume, cancel)
//! - Message serialization/deserialization for XPC dictionaries
//! - Security validation: code signature and bundle ID verification
//! - User authentication: mapping XPC connections to user accounts
//! - Type-safe dictionary access with error handling
//!
//! Security Model:
//! The XPC service implements a privileged helper pattern where the GUI application
//! communicates with a privileged helper process via Apple's blessed Mach services.
//! All messages are validated for code signature and bundle identity before processing.
//!
//! Message Flow:
//! 1. GUI creates XPC connection to helper (client mode)
//! 2. GUI sends authenticated message with request code
//! 3. Helper validates sender's code signature and bundle ID
//! 4. Helper processes request and sends response
//! 5. GUI receives and parses response
//!
//! This module is critical to security - all validation happens here.

const std = @import("std");
const builtin = @import("builtin");
const k = @import("../constants.zig").k;
const c = @import("../types.zig").c;
const Debug = @import("../util/debug.zig");
const isMacOS = @import("../types.zig").isMacOS;

const xpc = @cImport(@cInclude("xpc_helper.h"));

/// Type alias for C connection handles
pub const XPCConnection = xpc.xpc_connection_t;

/// Type alias for C dispatch queues
pub const XPCDispatchQueue = xpc.dispatch_queue_t;

/// Type alias for C dictionary/message objects
pub const XPCObject = xpc.xpc_object_t;

const Constants = @import("../constants.zig");

const HelperRequestCode = Constants.HelperRequestCode;
const HelperResponseCode = Constants.HelperResponseCode;
const Character = Constants.Character;

const NullTerminatedStringType: type = [:0]const u8;

/// C-convention function pointer for XPC message handlers
/// Receives connection and message, must handle response sending
const XPCRequestHandler = *const fn (connection: xpc.xpc_connection_t, message: xpc.xpc_object_t) callconv(.c) void;

/// Configuration for XPC service initialization
/// Specifies whether this is server (helper) or client (GUI) mode
/// and provides bundle IDs for security validation
const XPCServiceConfig = struct {
    isServer: bool = false, // true for helper, false for GUI
    serverBundleId: [:0]const u8, // Bundle ID of the helper
    clientBundleId: [:0]const u8 = undefined, // Bundle ID of the GUI (client only)
    serviceName: []const u8, // Human-readable service name
    requestHandler: XPCRequestHandler, // Callback for incoming messages
};

/// Error set for XPC dictionary operations
pub const DictionaryError = error{
    MissingKey, // Required key not found in dictionary
    UnexpectedType, // Value exists but wrong type
    NullString, // String value is null pointer
};

/// Simple timer for request rate limiting
const XPCRequestTimer = struct {
    timeOfLastRequest: i64 = 0,
    isTimerSet: bool = false,

    /// Starts the timer by recording current timestamp
    pub fn start(self: *XPCRequestTimer) void {
        self.timeOfLastRequest = std.time.timestamp();
        self.isTimerSet = true;
    }

    /// Resets the timer
    pub fn reset(self: *XPCRequestTimer) void {
        self.timeOfLastRequest = 0;
        self.isTimerSet = false;
    }
};

/// Manages XPC connection lifecycle and message handling.
/// Wraps lower-level XPC APIs to provide type-safe connection management
/// for both client (GUI) and server (helper) modes.
pub const XPCService = struct {
    service: XPCConnection = undefined, // XPC connection handle
    clientDispatchQueue: XPCDispatchQueue = undefined, // queue for client message handling
    config: XPCServiceConfig, // Configuration (bundle IDs, mode, etc.)
    timer: XPCRequestTimer = .{}, // Request rate limiting timer

    const Self = @This();

    /// Initializes the service configuration without establishing the connection.
    /// Validates that client mode has a client bundle ID specified.
    /// The actual Mach connection is created later by calling start().
    ///
    /// `Returns`:
    ///   XPCService instance (not yet connected)
    ///
    /// `Errors`:
    ///   error.ClientMustSpecifyCliendBundleIdInXPCConfig: Client mode without bundle ID
    pub fn init(config: XPCServiceConfig) !Self {
        Debug.log(.INFO, "{s}: Initializing XPC Service...", .{config.serviceName});

        if (!config.isServer and config.clientBundleId.len < 1) return error.ClientMustSpecifyCliendBundleIdInXPCConfig;

        return Self{
            .config = config,
        };
    }

    /// Establishes the Mach service connection and begins listening for messages.
    /// For servers: creates listener and starts dispatch_main() (blocking)
    /// For clients: connects to helper and sends initial ping (non-blocking)
    ///
    /// `Server Mode`:
    ///   - Creates listener socket on Mach service
    ///   - Registers message handler
    ///   - Blocks at dispatch_main() until application exit
    ///   - Requires launchd service definition (.plist)
    ///
    /// `Client Mode`:
    ///   - Connects to privileged helper's Mach service
    ///   - Creates dispatch queue for async message handling
    ///   - Sends initial INITIAL_PING to verify connection
    ///   - Returns immediately (non-blocking)
    ///   - Sleeps 100ms to allow helper to start up
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

    /// C-convention event handler for listener socket connections.
    /// Called by XPC when a new client connects to the privileged helper.
    /// Validates connection type and registers message handler.
    ///
    /// `Arguments`:
    ///   connection: New XPC connection from a client
    ///   msgHandler: Message handler callback for this connection
    ///
    /// `Process`:
    ///   1. Verify connection is actually an XPC_TYPE_CONNECTION
    ///   2. Register message handler for the connection
    ///   3. Resume the connection to begin receiving messages
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

    /// Retrieves the home directory of the client application's user.
    /// Uses XPC audit token to get user ID (UID), then maps to passwd entry.
    /// Rejects root (UID 0) for security - privileged helper must be invoked by normal user.
    ///
    /// `Arguments`:
    ///   connection: XPC connection to extract audit token from
    ///
    /// `Returns`:
    ///   Home directory path as string (e.g., "/Users/{user}")
    ///
    /// `Errors`:
    ///   error.ClientApplicationRunningAsRootIsDisallowedBySecurityPolicy: UID is 0
    ///   error.UnableToMapUserToEUID: passwd entry not found for UID
    ///   error.UnableToMapUserHomeDirectory: passwd entry has no home directory
    ///
    /// `Security`:
    ///   - Rejects root to prevent privilege escalation
    ///   - Uses audit token (kernel-verified) not client-supplied UID
    pub fn getUserHomePath(connection: XPCConnection) ![]const u8 {
        const euid: c_uint = c.xpc_connection_get_euid(@ptrCast(connection));
        if (euid == 0) return error.ClientApplicationRunningAsRootIsDisallowedBySecurityPolicy;

        const userEntry = c.getpwuid(euid);
        if (userEntry == null) return error.UnableToMapUserToEUID;

        if (userEntry.*.pw_dir == null) return error.UnableToMapUserHomeDirectory;

        return std.mem.span(userEntry.*.pw_dir);
    }

    /// Validates that an XPC message came from the expected, legitimate client.
    /// Verifies code signature and checks bundle ID and team ID match expected values.
    /// This is the primary security check for message origin validation.
    ///
    /// `Arguments`:
    ///   message: XPC message to validate
    ///   authenticClientBundleId: Expected bundle ID (e.g., "com.example.app")
    ///   authenticClientTeamId: Expected team ID (e.g., "ABC123DEF4")
    ///
    /// `Returns`:
    ///   true if both bundle ID and team ID match and signature is valid
    ///   false on any validation failure
    ///
    /// `Validation Steps`:
    ///   1. Create SecCode reference from XPC message
    ///   2. Verify code signature is valid (not tampered)
    ///   3. Extract code signing information dictionary
    ///   4. Compare bundle ID against expected
    ///   5. Compare team ID against expected
    ///   6. Return true only if all checks pass
    ///
    /// `Security`:
    ///   - Code signature validation ensures app hasn't been modified
    ///   - Bundle ID prevents wrong app from using the helper
    ///   - Team ID ensures app is from trusted developer
    ///   - Returns false on any error
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

    /// Sends initial ping message to verify helper connection.
    /// Helps detect if helper service has started successfully.
    pub fn pingServer(connection: XPCConnection) void {
        Debug.log(.INFO, "Sending initial ping to the Helper. Awaiting response...", .{});
        const ping = createRequest(.INITIAL_PING);
        defer releaseObject(ping);
        connectionSendMessage(connection, ping);
    }

    /// Creates an XPC request message dictionary.
    /// Initializes dictionary with request code as int64 value.
    ///
    /// `Arguments`:
    ///   value: Request code (enum value specifying what operation)
    ///
    /// `Returns`:
    ///   XPC dictionary object (caller must release with releaseObject)
    ///
    /// `Message Format`:
    ///   {"request": <HelperRequestCode as i64>}
    pub fn createRequest(value: HelperRequestCode) XPCObject {
        const dict: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
        xpc.xpc_dictionary_set_int64(dict, "request", @intFromEnum(value));
        return dict;
    }

    /// Extracts request code from XPC request dictionary.
    /// Validates key exists and converts from i64 to enum.
    pub fn parseRequest(dict: XPCObject) DictionaryError!HelperRequestCode {
        const raw = try getInt64(dict, "request");
        return @enumFromInt(raw);
    }

    /// Creates an XPC response message dictionary.
    /// Initializes dictionary with response code as int64 value.
    ///
    /// `Arguments`:
    ///   value: Response code (enum indicating success/failure)
    ///
    /// `Returns`:
    ///   XPC dictionary object (caller must release with releaseObject)
    ///
    /// `Message Format`:
    ///   {"response": <HelperResponseCode as i64>}
    pub fn createResponse(value: HelperResponseCode) XPCObject {
        const dict: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
        xpc.xpc_dictionary_set_int64(dict, "response", @intFromEnum(value));
        return dict;
    }

    /// Extracts response code from XPC response dictionary.
    pub fn parseResponse(dict: XPCObject) DictionaryError!HelperResponseCode {
        const raw = try getInt64(dict, "response");
        return @enumFromInt(raw);
    }

    /// Sets a string value in XPC dictionary.
    /// Both key and value must be null-terminated C strings.
    pub fn createString(dict: XPCObject, key: [:0]const u8, value: [:0]const u8) void {
        xpc.xpc_dictionary_set_string(dict, @ptrCast(key), @ptrCast(value));
    }

    /// Gets string value from XPC dictionary.
    /// Validates key exists and value is string type.
    ///
    /// `Returns`:
    ///   Null-terminated string from dictionary
    ///
    /// `Errors`:
    ///   error.MissingKey: Key not in dictionary
    ///   error.UnexpectedType: Value exists but is not string
    ///   error.NullString: String pointer is null
    pub fn parseString(dict: XPCObject, key: [:0]const u8) DictionaryError![:0]const u8 {
        _ = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_STRING);
        const c_str = xpc.xpc_dictionary_get_string(dict, @ptrCast(key));
        if (c_str == null) return DictionaryError.NullString;
        const ptr: [*:0]const u8 = @ptrCast(c_str);
        return std.mem.span(ptr);
    }

    /// Sets signed 64-bit integer value in XPC dictionary
    pub fn createInt64(dict: XPCObject, key: [:0]const u8, value: i64) void {
        xpc.xpc_dictionary_set_int64(dict, @ptrCast(key), value);
    }

    /// Gets signed 64-bit integer value from XPC dictionary.
    /// Validates key exists and value is int64 type.
    pub fn getInt64(dict: XPCObject, key: [:0]const u8) DictionaryError!i64 {
        _ = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_INT64);
        return xpc.xpc_dictionary_get_int64(dict, @ptrCast(key));
    }

    /// Sets unsigned 64-bit integer value in XPC dictionary
    pub fn createUInt64(dict: XPCObject, key: [:0]const u8, value: u64) void {
        xpc.xpc_dictionary_set_uint64(dict, @ptrCast(key), value);
    }

    /// Gets unsigned 64-bit integer value from XPC dictionary.
    /// Validates key exists and value is uint64 type.
    pub fn getUInt64(dict: XPCObject, key: [:0]const u8) DictionaryError!u64 {
        _ = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_UINT64);
        return xpc.xpc_dictionary_get_uint64(dict, @ptrCast(key));
    }

    /// Adds a file descriptor to XPC dictionary.
    /// XPC automatically handles fd reference counting.
    pub fn createFileDescriptor(dict: XPCObject, key: [:0]const u8, value: c_int) void {
        const fdObj: XPCObject = xpc.xpc_fd_create(value);
        if (fdObj == null) return;
        xpc.xpc_dictionary_set_value(dict, @ptrCast(key), fdObj);
        xpc.xpc_release(fdObj);
    }

    /// Gets file descriptor from XPC dictionary.
    /// Duplicates the fd (caller becomes owner and must close).
    /// Validates key exists and value is fd type.
    ///
    /// `Returns`:
    ///   Duplicated file descriptor (caller responsible for close)
    ///
    /// `Errors`:
    ///   error.MissingKey: Key not in dictionary
    ///   error.UnexpectedType: Value exists but is not fd type
    pub fn getFileDescriptor(dict: XPCObject, key: [:0]const u8) DictionaryError!c_int {
        const value = try requireDictionaryValue(dict, key, xpc.XPC_TYPE_FD);
        // xpc_dictionary_dup_fd performs the type check but returns -1 on failure.
        const fd = xpc.xpc_dictionary_dup_fd(dict, @ptrCast(key));
        if (fd == -1) return DictionaryError.UnexpectedType;
        _ = value; // already retained by dup_fd
        return fd;
    }

    /// Releases an XPC object (dictionary, message, etc).
    /// Decrements reference count; can safely call multiple times.
    pub fn releaseObject(obj: XPCObject) void {
        xpc.xpc_release(obj);
    }

    /// Flushes pending messages on XPC connection.
    /// Ensures all queued messages are sent immediately.
    pub fn connectionFlush(connection: XPCConnection) void {
        xpc.XPCConnectionFlush(connection);
    }
};

/// Validates that a dictionary key exists with the expected type.
/// Used internally to type-check values before extraction.
///
/// `Arguments`:
///   dict: XPC dictionary to check
///   key: Dictionary key to validate
///   expectedType: XPC type that should be present
///
/// `Returns`:
///   The value object if validation passes
///
/// `Errors`:
///   error.MissingKey: Key not found in dictionary
///   error.UnexpectedType: Value type doesn't match expected
fn requireDictionaryValue(dict: XPCObject, key: [:0]const u8, comptime expectedType: xpc.xpc_type_t) DictionaryError!XPCObject {
    const value = xpc.xpc_dictionary_get_value(dict, @ptrCast(key));
    if (value == null) return DictionaryError.MissingKey;

    const value_type = xpc.xpc_get_type(value);
    if (value_type != expectedType) return DictionaryError.UnexpectedType;

    return value;
}

/// Validates that a CFDictionary string value matches expected value.
/// Used for code signature validation (bundle ID, team ID, etc).
///
/// `Arguments`:
///   dictionary: CFDictionary from Security framework
///   key: CFString key to look up
///   validString: Expected value (null-terminated)
///
/// `Returns`:
///   true if dictionary value equals validString, false otherwise
///   Returns false on any error (fail-safe)
fn validateDictionaryString(dictionary: c.CFDictionaryRef, key: c.CFStringRef, validString: [:0]const u8) bool {
    const stringBuffer = getStringFromDictionary(dictionary, key) catch |err| {
        if (err == error.UnableToRetrieveStringFromRef) Debug.log(.ERROR, "Unable to retreive string from Ref... Expected: '{s}'. Error: {any}", .{ validString, err });
        return false;
    };

    const finalString: [:0]const u8 = @ptrCast(std.mem.sliceTo(&stringBuffer, Character.NULL));

    // Debug.log(.INFO, "validateDictionaryString(): Expected '{s}', retreived: '{s}'.", .{ validString, finalString });

    return std.mem.eql(u8, finalString, validString);
}

/// Extracts a CFString from CFDictionary and converts to Zig string.
/// Used during code signature validation to extract bundle ID and team ID.
///
/// `Arguments`:
///   dictionary: CFDictionary containing the value
///   key: CFString key to look up
///
/// `Returns`:
///   Fixed-size buffer (512 bytes) containing null-terminated string
///
/// `Errors`:
///   error.UnableToRetrieveStringFromRef: Key not found or CFString conversion failed
///   error.StringIsTooShortToBeMeaningful: Extracted string too short (< 2 chars)
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
