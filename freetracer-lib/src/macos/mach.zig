const std = @import("std");
const builtin = @import("builtin");
const k = @import("../constants.zig").k;
const c = @import("../types.zig").c;
const Debug = @import("../util/debug.zig");
const isMacOS = @import("../types.zig").isMacOS;

const xpc = @cImport(@cInclude("xpc_helper.h"));
const NullTerminatedStringType: type = [:0]const u8;

const XPCRequestHandler = *const fn (connection: xpc.xpc_connection_t, message: xpc.xpc_object_t) callconv(.c) void;

const XPCServiceConfig = struct {
    isServer: bool = false,
    serverBundleId: []const u8,
    serviceName: []const u8,
    requestHandler: XPCRequestHandler,
};

pub const XPCService = struct {
    service: xpc.xpc_connection_t = undefined,
    client_queue: ?xpc.dispatch_queue_t = null,
    config: XPCServiceConfig,

    const Self = @This();

    pub fn init(config: XPCServiceConfig) Self {
        Debug.log(.INFO, "Initializing XPC Service...", .{});

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

        if (self.config.isServer)
            xpc.XPCConnectionSetEventHandler(self.service, @ptrCast(&connectionHandler), @ptrCast(self.config.requestHandler))
        else {
            self.client_queue = xpc.dispatch_queue_create("com.orbitixx.freetracer.xpc-queue", null);
            xpc.XPCMessageSetEventHandler(self.service, @ptrCast(&self.config.requestHandler));
            xpc.xpc_connection_set_target_queue(self.service, self.client_queue.?);
        }

        xpc.xpc_connection_resume(self.service);

        Debug.log(.INFO, "{s}: Service started, listening for connections...", .{self.config.serviceName});

        if (self.config.isServer) xpc.dispatch_main() else self.sendMessage("ping");
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
    }

    pub fn deinit(self: *Self) void {
        xpc.xpc_connection_cancel(self.service);
        xpc.xpc_release(self.service);

        if (!self.config.isServer and self.client_queue != null) {
            // xpc.dispatch_release(self.client_queue.?);
        }
    }
};

// pub const XPCClient = struct {
//     service: xpc.xpc_connection_t = undefined,
//     clientBundleId: [*:0]const u8,
//
//     const Self = @This();
//
//     pub fn init(clientBundleId: [*:0]const u8) Self {
//         return Self{
//             .clientBundleId = clientBundleId,
//         };
//     }
//
//     pub fn start(self: *Self) void {
//         self.service = xpc.xpc_connection_create_mach_service(@ptrCast(self.clientBundleId), null, xpc.XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
//
//         if (self.service == null) {
//             Debug.log(.ERROR, "XPC Client is unable to create a mach service. Aborting...", .{});
//             return;
//         }
//
//         xpc.XPCMessageSetEventHandler(self.service, @ptrCast(&messageHandler));
//         xpc.xpc_connection_resume(self.service);
//         self.sendMessage("HELLO TEST TEST");
//
//         Debug.log(.INFO, "XPC client started...", .{});
//
//         xpc.dispatch_main();
//     }
//
//     pub fn messageHandler(connection: xpc.xpc_connection_t, message: xpc.xpc_object_t) callconv(.c) void {
//         _ = connection;
//         Debug.log(.INFO, "CLIENT: Message Handler executed!", .{});
//
//         const reply_type = xpc.xpc_get_type(message);
//
//         if (reply_type == xpc.XPC_TYPE_DICTIONARY) {
//             const status = xpc.xpc_dictionary_get_string(message, "status");
//             const response = xpc.xpc_dictionary_get_string(message, "response");
//
//             if (status != null and response != null) {
//                 Debug.log(.INFO, "Helper replied - Status: {s}, Response: {s}", .{ status, response });
//             }
//         }
//     }
//
//     pub fn sendMessage(self: *Self, message: [*:0]const u8) void {
//         const msg: xpc.xpc_object_t = xpc.xpc_dictionary_create(null, null, 0);
//         defer xpc.xpc_release(msg);
//
//         xpc.xpc_dictionary_set_string(msg, "request", "hello");
//         xpc.xpc_dictionary_set_string(msg, "data", message);
//
//         xpc.xpc_connection_send_message(self.service, msg);
//     }
//
//     pub fn deinit(self: *Self) void {
//         xpc.xpc_connection_cancel(self.service);
//         xpc.xpc_release(self.service);
//     }
// };

pub const SerializedData = struct {
    data: [k.MachPortPacketSize]u8,

    pub fn serialize(comptime T: type, rawData: T) !SerializedData {
        var data = std.mem.zeroes([k.MachPortPacketSize]u8);

        switch (T) {
            NullTerminatedStringType => {
                std.debug.assert(rawData.len + 1 <= k.MachPortPacketSize); // +1 for null terminator
                @memcpy(data[0..rawData.len], rawData);
                data[rawData.len] = 0x00;
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
                // const len = std.mem.indexOfScalar(u8, &sData.data, 0x00) orelse blk: {
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

        Debug.log(.INFO, "{s}: Request data received: {any}\n", .{ AppName, std.mem.sliceTo(&requestData.data, 0x00) });

        var responseData = processMessageFn(msgId, requestData) catch |err| blk: {
            Debug.log(.ERROR, "{s}: onMessageReceived.processRequestMessage(msgId = {d}) returned an error: {any}", .{ AppName, msgId, err });
            break :blk SerializedData{ .data = std.mem.zeroes([k.MachPortPacketSize]u8) };
        };

        returnData = @ptrCast(responseData.constructCFDataRef());

        Debug.log(.INFO, "{s}: Successfully packaged response: {any}.", .{ AppName, std.mem.sliceTo(&responseData.data, 0x00) });

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
