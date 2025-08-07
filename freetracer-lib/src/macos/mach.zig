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
    serverBundleId: []const u8,
    clientBundleId: []const u8 = undefined,
    serviceName: []const u8,
    requestHandler: XPCRequestHandler,
};

pub const XPCService = struct {
    service: XPCConnection = undefined,
    clientDispatchQueue: XPCDispatchQueue = undefined,
    config: XPCServiceConfig,

    const Self = @This();

    pub fn init(config: XPCServiceConfig) !Self {
        Debug.log(.INFO, "{s}: Initializing XPC Service...", .{config.serviceName});

        if (!config.isServer and config.clientBundleId.len < 1) return error.ClientMustSpecifyCliendBundleIdInXPCConfig;

        return Self{
            .config = config,
        };
    }

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
            std.time.sleep(100_000);
            pingServer(self.service);
        }
    }

    pub fn connectionHandler(connection: xpc.xpc_connection_t, msgHandler: xpc.XPCMessageHandler) callconv(.c) void {
        const connectionType = xpc.xpc_get_type(connection);

        if (connectionType == xpc.XPC_TYPE_CONNECTION) {
            Debug.log(.INFO, "New XPC connection established", .{});
            xpc.XPCMessageSetEventHandler(connection, msgHandler);
            xpc.xpc_connection_resume(connection);
        }
    }

    pub fn sendMessage(self: *Self, message: [*:0]const u8) void {
        const msg: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
        defer xpc.xpc_release(msg);

        xpc.xpc_dictionary_set_string(msg, "request", "hello");
        xpc.xpc_dictionary_set_string(msg, "data", message);

        xpc.xpc_connection_send_message(self.service, msg);

        // xpc.XPCConnectionSendMessageWithReply(self.service, msg, self.clientDispatchQueue, @ptrCast(self.config.requestHandler));
    }

    pub fn connectionSendMessage(connection: XPCConnection, dataDictionary: XPCObject) void {
        xpc.xpc_connection_send_message(connection, dataDictionary);
    }

    pub fn getUserHomePath(connection: XPCConnection) ![]const u8 {
        const euid: c_uint = c.xpc_connection_get_euid(@ptrCast(connection));

        if (euid == 0) return error.ClientApplicationIsRunningAsRootIsDisallowedBySecurityPolicy;

        const userEntry = c.getpwuid(euid);

        if (userEntry == null) return error.UnableToMapUserToEUID;

        return std.mem.span(userEntry.*.pw_dir);
    }

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
        xpc.xpc_connection_cancel(self.service);
        xpc.xpc_release(self.service);
    }

    pub fn pingServer(connection: XPCConnection) void {
        const ping = createRequest(.INITIAL_PING);
        defer releaseObject(ping);
        connectionSendMessage(connection, ping);
    }

    pub fn createRequest(value: HelperRequestCode) XPCObject {
        const dict: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
        xpc.xpc_dictionary_set_int64(dict, "request", @intFromEnum(value));
        return dict;
    }

    pub fn parseRequest(dict: XPCObject) HelperRequestCode {
        return @enumFromInt(xpc.xpc_dictionary_get_int64(dict, "request"));
    }

    pub fn createResponse(value: HelperResponseCode) XPCObject {
        const dict: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
        xpc.xpc_dictionary_set_int64(dict, "response", @intFromEnum(value));
        return dict;
    }

    pub fn parseResponse(dict: XPCObject) HelperResponseCode {
        return @enumFromInt(xpc.xpc_dictionary_get_int64(dict, "response"));
    }

    pub fn createString(dict: XPCObject, key: []const u8, value: []const u8) void {
        xpc.xpc_dictionary_set_string(dict, @ptrCast(key), @ptrCast(value));
    }

    pub fn parseString(dict: XPCObject, key: []const u8) []const u8 {
        return std.mem.span(xpc.xpc_dictionary_get_string(dict, @ptrCast(key)));
    }

    pub fn createInt64(dict: XPCObject, key: []const u8, value: i64) void {
        xpc.xpc_dictionary_set_int64(dict, @ptrCast(key), value);
    }

    pub fn getInt64(dict: XPCObject, key: []const u8) i64 {
        return xpc.xpc_dictionary_get_int64(dict, @ptrCast(key));
    }

    pub fn releaseObject(obj: XPCObject) void {
        xpc.xpc_release(obj);
    }
};

fn validateDictionaryString(dictionary: c.CFDictionaryRef, key: c.CFStringRef, validString: [:0]const u8) bool {
    const stringBuffer = getStringFromDictionary(dictionary, key) catch |err| {
        if (err == error.UnableToRetrieveStringFromRef) Debug.log(.ERROR, "Unable to retreive string from Ref... Expected: '{s}'. Error: {any}", .{ validString, err });
        return false;
    };

    const finalString: [:0]const u8 = @ptrCast(std.mem.sliceTo(&stringBuffer, Character.NULL));

    Debug.log(.INFO, "validateDictionaryString(): Expected '{s}', retreived: '{s}'.", .{ validString, finalString });

    return std.mem.eql(u8, finalString, validString);
}

fn getStringFromDictionary(dictionary: c.CFDictionaryRef, key: c.CFStringRef) ![512]u8 {
    // Pre-allocate a large enough buffer to avoid stack overflow vector of attack
    var resultBuffer: [512]u8 = std.mem.zeroes([512]u8);

    const resultValueRef: c.CFStringRef = @ptrCast(c.CFDictionaryGetValue(dictionary, key));
    const stringParsingResult: c.Boolean = c.CFStringGetCString(resultValueRef, &resultBuffer, resultBuffer.len, c.kCFStringEncodingUTF8);

    if (stringParsingResult != c.TRUE) {
        return error.UnableToRetrieveStringFromRef;
    }

    if (resultBuffer.len < 2) {
        Debug.log(.ERROR, "Retrieved string is too short to be meaningful: '{s}'.", .{std.mem.sliceTo(&resultBuffer, Character.NULL)});
        return error.StringIsTooShortToBeMeaningful;
    }

    return resultBuffer;
}

pub const SerializedData = struct {
    data: [k.MachPortPacketSize]u8,

    pub fn serialize(comptime T: type, rawData: T) !SerializedData {
        var data = std.mem.zeroes([k.MachPortPacketSize]u8);

        switch (T) {
            NullTerminatedStringType => {
                std.debug.assert(rawData.len + 1 <= k.MachPortPacketSize); // +1 for null terminator
                @memcpy(data[0..rawData.len], rawData);
                data[rawData.len] = Character.NULL;
            },

            @TypeOf(null) => {},

            else => {
                std.debug.assert(@sizeOf(T) <= k.MachPortPacketSize);
                const bytes = std.mem.asBytes(&rawData);
                @memcpy(data[0..bytes.len], bytes);
            },
        }

        return .{
            .data = data,
        };
    }

    pub fn deserialize(comptime T: type, sData: SerializedData) !T {
        switch (T) {
            NullTerminatedStringType => {
                // // Find the null terminator to determine string length
                // const len = std.mem.indexOfScalar(u8, &sData.data, Character.NULL) orelse blk: {
                //     Debug.log(.WARNING, "No null terminator found in serialized string data, using full possible data length.", .{});
                //     break :blk k.MachPortPacketSize;
                // };

                return sData.data;
            },

            @TypeOf(null) => {
                return null;
            },

            else => {
                var sArray: [k.MachPortPacketSize]u8 = sData.data;
                return std.mem.bytesAsValue(T, &sArray).*;
            },
        }
    }

    pub fn constructCFDataRef(self: SerializedData) c.CFDataRef {
        return c.CFDataCreate(c.kCFAllocatorDefault, @ptrCast(&self.data), @intCast(self.data.len));
    }

    pub fn destructCFDataRef(dataRef: c.CFDataRef) !SerializedData {
        if (dataRef == null) return error.CFDataRefIsNULL;

        const sourceData = @as([*]const u8, c.CFDataGetBytePtr(dataRef))[0..@intCast(c.CFDataGetLength(dataRef))];

        var finalByteArray: [k.MachPortPacketSize]u8 = std.mem.zeroes([k.MachPortPacketSize]u8);
        @memcpy(finalByteArray[0..sourceData.len], sourceData);

        return SerializedData{
            .data = finalByteArray,
        };
    }
};

pub const MachCommunicator = struct {
    pub const MachCommunicatorConfig = struct {
        localBundleId: []const u8,
        remoteBundleId: []const u8,
        ownerName: []const u8,
        processMessageFn: *const fn (msgId: i32, requestData: SerializedData) anyerror!SerializedData,
    };

    pub var AppName: []const u8 = "UNKNOWN";
    pub var processMessageFn: *const fn (msgId: i32, requestData: SerializedData) anyerror!SerializedData = MachCommunicator.defaultProcessMessageFn;

    config: MachCommunicatorConfig,
    allocator: std.mem.Allocator,
    localMessagePortNameRef: c.CFStringRef = null,
    localMessagePortContext: c.CFMessagePortContext = .{},
    shouldFreeMessagePortInfo: c.Boolean = c.FALSE,
    localMessagePortRef: c.CFMessagePortRef = null,
    runLoopSourceRef: c.CFRunLoopSourceRef = null,

    pub fn init(allocator: std.mem.Allocator, config: MachCommunicatorConfig) MachCommunicator {
        AppName = config.ownerName;
        processMessageFn = config.processMessageFn;

        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn start(self: *MachCommunicator) !void {
        self.localMessagePortNameRef = c.CFStringCreateWithCStringNoCopy(
            c.kCFAllocatorDefault,
            @ptrCast(self.config.localBundleId),
            c.kCFStringEncodingUTF8,
            c.kCFAllocatorNull,
        );

        self.localMessagePortContext = c.CFMessagePortContext{
            .version = 0,
            .copyDescription = null,
            .info = null,
            .release = null,
            .retain = null,
        };

        self.localMessagePortRef = c.CFMessagePortCreateLocal(
            c.kCFAllocatorDefault,
            self.localMessagePortNameRef,
            MachCommunicator.onMessageReceived,
            &self.localMessagePortContext,
            &self.shouldFreeMessagePortInfo,
        );

        if (self.localMessagePortRef == null) {
            Debug.log(.ERROR, "{s}: unable to create a local message port.", .{AppName});
            return;
        }

        const kRunLoopOrder: c.CFIndex = 0;

        const runLoopSource: c.CFRunLoopSourceRef = c.CFMessagePortCreateRunLoopSource(c.kCFAllocatorDefault, self.localMessagePortRef, kRunLoopOrder);
        c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), runLoopSource, c.kCFRunLoopDefaultMode);

        Debug.log(.INFO, "{s}: MachCommunicator started. Awaiting requests...", .{AppName});

        c.CFRunLoopRun();
    }

    // NOTE: Static function/callback. Arguments are frozen and dictacted by c.CFMessagePortCreateLocal signature.
    pub fn onMessageReceived(port: c.CFMessagePortRef, msgId: c.SInt32, data: c.CFDataRef, info: ?*anyopaque) callconv(.C) c.CFDataRef {
        var returnData: c.CFDataRef = null;

        _ = port;
        _ = info;

        Debug.log(.INFO, "{s}: onMessageReceived callback executing...", .{AppName});

        const requestData = SerializedData.destructCFDataRef(@ptrCast(data)) catch |err| {
            Debug.log(.WARNING, "{s}: onMessageReceived(): received NULL data as parameter. Error: {any}. Ignoring request...", .{ AppName, err });
            return returnData;
        };

        if (requestData.data.len < 1) {
            Debug.log(.WARNING, "{s}: The received length of the request data is 0.", .{AppName});
            return returnData;
        }

        Debug.log(.INFO, "{s}: Request data received: {any}\n", .{ AppName, std.mem.sliceTo(&requestData.data, Character.NULL) });

        var responseData = processMessageFn(msgId, requestData) catch |err| blk: {
            Debug.log(.ERROR, "{s}: onMessageReceived.processRequestMessage(msgId = {d}) returned an error: {any}", .{ AppName, msgId, err });
            break :blk SerializedData{ .data = std.mem.zeroes([k.MachPortPacketSize]u8) };
        };

        returnData = @ptrCast(responseData.constructCFDataRef());

        Debug.log(.INFO, "{s}: Successfully packaged response: {any}.", .{ AppName, std.mem.sliceTo(&responseData.data, Character.NULL) });

        return returnData;
    }

    pub fn deinit(self: MachCommunicator) void {
        // defer is used to preserve execution order to follow the order
        // in which these were initialized/allocated.
        defer _ = c.CFRelease(self.localMessagePortNameRef);
        defer _ = c.CFRelease(self.localMessagePortRef);
        defer _ = c.CFRelease(self.runLoopSourceRef);
        defer c.CFRunLoopSourceInvalidate(self.runLoopSourceRef);
    }

    pub fn defaultProcessMessageFn(msgId: i32, requestData: SerializedData) !SerializedData {
        _ = msgId;
        _ = requestData;

        return error.MachCommunicatorProcessMessageFunctionNotInitialized;
    }

    pub fn sendMachMessageToRemote(self: MachCommunicator, comptime requestType: type, requestData: requestType, msgId: i32, comptime returnType: type) !returnType {
        if (!isMacOS) return error.CallAllowedOnMacOSOnly;

        // Create a CString from the Privileged Tool's Apple App Bundle ID
        const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
            c.kCFAllocatorDefault,
            @ptrCast(self.config.remoteBundleId),
            c.kCFStringEncodingUTF8,
            c.kCFAllocatorNull,
        );
        defer _ = c.CFRelease(portNameRef);

        const remoteMessagePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, portNameRef);

        if (remoteMessagePort == null) {
            Debug.log(.ERROR, "Freetracer unable to create a remote message port to Freetracer Helper Tool.", .{});
            return error.UnableToCreateRemoteMessagePort;
        }

        defer _ = c.CFRelease(remoteMessagePort);

        const s_requestData = try SerializedData.serialize(requestType, requestData);

        const requestDataRef: c.CFDataRef = @ptrCast(s_requestData.constructCFDataRef());
        defer _ = c.CFRelease(requestDataRef);

        var responseDataRef: c.CFDataRef = null;
        var helperResponseCode: c.SInt32 = 0;

        Debug.log(.INFO, "Freetracer is preparing to send request to Privileged Helper Tool...", .{});

        helperResponseCode = c.CFMessagePortSendRequest(
            remoteMessagePort,
            msgId,
            requestDataRef,
            k.SendTimeoutInSeconds,
            k.ReceiveTimeoutInSeconds,
            c.kCFRunLoopDefaultMode,
            &responseDataRef,
        );

        if (helperResponseCode != c.kCFMessagePortSuccess or responseDataRef == null) {
            Debug.log(
                .ERROR,
                "Freetracer failed to communicate with Freetracer Helper Tool - received invalid response code ({d}) or null response data ({any})",
                .{ helperResponseCode, responseDataRef },
            );
            return error.FailedToCommunicateWithHelperTool;
        }

        // Debug.log(.DEBUG, "@sizeOf(responseDataRef) is: {d}", .{@sizeOf(responseDataRef)});
        const responseData = try SerializedData.destructCFDataRef(@ptrCast(responseDataRef));
        const deserializedData = try SerializedData.deserialize(returnType, responseData);

        return deserializedData;
    }

    pub fn testRemotePort(self: MachCommunicator) bool {
        Debug.log(.INFO, "{s} | remoteBundleId is: {s}.", .{ AppName, self.config.remoteBundleId });

        const remotePortNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
            c.kCFAllocatorDefault,
            @ptrCast(self.config.remoteBundleId),
            c.kCFStringEncodingUTF8,
            c.kCFAllocatorNull,
        );

        Debug.log(.INFO, "{s} | created remotePortNameRef.", .{AppName});

        const remotePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, remotePortNameRef);

        Debug.log(.INFO, "{s} | created remotePortRef.", .{AppName});

        defer _ = c.CFRelease(remotePort);
        defer _ = c.CFRelease(remotePortNameRef);

        if (remotePort == null) {
            Debug.log(.WARNING, "{s} | Failed to establish a mach connection to the test remote port.", .{AppName});
            return false;
        } else {
            Debug.log(.INFO, "{s} | Successfully tested the remote port.", .{AppName});
            return true;
        }
    }
};
