const std = @import("std");
const print = std.debug.print;

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    // @cInclude("xpc/xpc.h");
    // @cInclude("dispatch/dispatch.h");
    // @cInclude("Block.h");
});

// Define the Info.plist content directly in your main file
// comptime {
//     @export(@as([*:0]const u8, @ptrCast(
//         \\<?xml version="1.0" encoding="UTF-8"?>
//         \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
//         \\<plist version="1.0">
//         \\<dict>
//         \\    <key>CFBundleIdentifier</key>
//         \\    <string>com.example.your-app</string>
//         \\    <!-- Other Info.plist content here -->
//         \\</dict>
//         \\</plist>
//     )), .{ .name = "__info_plist", .section = "__TEXT,__info_plist" });
// }

const kUnmountDiskRequest: i32 = 101;
const kUnmountDiskResponse: i32 = 201;

pub fn main() !void {
    const idString = "com.orbitixx.freetracer-helper";

    const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        idString,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );
    defer _ = c.CFRelease(portNameRef);

    var messagePortContext = c.CFMessagePortContext{
        .version = 0,
        .copyDescription = null,
        .info = null,
        .release = null,
        .retain = null,
    };

    var shouldFreeInfo: c.Boolean = 0;

    const localMessagePort: c.CFMessagePortRef = c.CFMessagePortCreateLocal(
        c.kCFAllocatorDefault,
        portNameRef,
        messagePortCallback,
        &messagePortContext,
        &shouldFreeInfo,
    );

    if (localMessagePort == null) {
        std.log.err("Error: Freetracer Helper Tool unable to create a local message port.", .{});
        return;
    }

    defer _ = c.CFRelease(localMessagePort);

    const runLoopSource: c.CFRunLoopSourceRef = c.CFMessagePortCreateRunLoopSource(c.kCFAllocatorDefault, localMessagePort, 0);
    defer _ = c.CFRelease(runLoopSource);

    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), runLoopSource, c.kCFRunLoopDefaultMode);
    defer c.CFRunLoopSourceInvalidate(runLoopSource);

    std.log.info("Freetracer Heloper Tool started. Awaiting requests...", .{});

    c.CFRunLoopRun();
}

pub fn messagePortCallback(port: c.CFMessagePortRef, msgId: c.SInt32, data: c.CFDataRef, info: ?*anyopaque) callconv(.C) c.CFDataRef {
    var returnData: c.CFDataRef = null;

    _ = port;
    _ = info;
    _ = data;

    switch (msgId) {
        kUnmountDiskRequest => {
            std.log.info("Freetracer Helper Tool received DADiskUnmount() request {d}.", .{kUnmountDiskRequest});
        },
        else => {
            std.log.warn("WARNING: Freetracer Helper Tool received unknown request. Aborting repsponse...", .{});
        },
    }

    const result: i32 = 0;
    const resultBytePtr: [*c]const u8 = @ptrCast(&result);

    returnData = c.CFDataCreate(c.kCFAllocatorDefault, resultBytePtr, @sizeOf(i32));

    std.log.info("Freetracer Helper Tool successfully packaged response: {d}.", .{result});
    return returnData;
}

// extern fn xpc_connection_set_event_handler(
//     connection: c.xpc_connection_t,
//     handler: *const fn (c.xpc_object_t) callconv(.C) void,
// ) void;
// extern fn xpc_connection_set_event_handler(connection: c.xpc_connection_t, handler: XpcHandlerBlock) void;
// extern fn xpc_connection_create_mach_service(name: [*c]const u8, queue: ?*anyopaque, flags: u64) c.xpc_connection_t;
//
// pub fn main() !void {
//     print(":: Freetracer-Helper: Privileged Helper Tool for Freetracer is running.", .{});
//
//     const maybe_service = xpc_connection_create_mach_service(
//         "com.orbitixx.freetracer-helper",
//         c.dispatch_get_main_queue(),
//         c.XPC_CONNECTION_MACH_SERVICE_LISTENER,
//     );
//
//     if (maybe_service == null) std.debug.panic("ERROR: Unable to create an XPC Mach service. xpc_connection_create_mach_service returned NULL.", .{});
//
//     const service = maybe_service.?;
//     defer c.xpc_release(service);
//
//     const serviceHandler = createXpcHandlerBlock(xpcServiceEventHandler);
//
//     xpc_connection_set_event_handler(service, serviceHandler);
//
//     c.xpc_connection_resume(service);
//     c.dispatch_main();
// }
//
// const XpcHandlerBlock = *const fn (?*anyopaque) callconv(.C) void;
//
// fn createXpcHandlerBlock(comptime callback: fn (c.xpc_object_t) void) XpcHandlerBlock {
//     const Block = struct {
//         fn handler(obj: ?*anyopaque) callconv(.C) void {
//             if (obj != null) {
//                 const n_obj: c.xpc_object_t = @ptrCast(obj);
//                 callback(n_obj);
//             }
//         }
//     };

// This would need proper Block API usage via extern functions
// In real code, you'd need to properly create a Block using _Block_copy
// For demonstration, we're just returning a function pointer
//     const blockHandler: XpcHandlerBlock = @ptrCast(&Block.handler);
//     return blockHandler;
// }
//
// pub fn xpcServiceEventHandler(service_object: c.xpc_object_t) void {
//     if (c.xpc_get_type(service_object) != c.XPC_TYPE_CONNECTION) return;
//
//     const connection: c.xpc_connection_t = @ptrCast(service_object);
//     handleXpcConnection(connection);
// }
//
// pub fn handleXpcConnection(connection: c.xpc_connection_t) void {
//     // c.xpc_connection_set_event_handler(connection, xpcConnectionEventHandler);
//     c.xpc_connection_resume(connection);
// }

// pub const xpcConnectionEventHandler = struct {
//     fn callback(message_object: c.xpc_object_t) callconv(.C) void {
//         if (c.xpc_get_type(message_object) != c.XPC_TYPE_DICTIONARY) return;
//
//         const reply = c.xpc_dictionary_create_reply(message_object);
//
//         handleXpcMessage(message_object, reply);
//
//         const maybe_connection = c.xpc_dictionary_get_remote_connection(message_object);
//         if (!maybe_connection) std.debug.panic("ERROR: Unable to capture XPC connection associated with a message object.", .{});
//
//         const connection = maybe_connection.?;
//         // defer c.xpc_release(connection);
//
//         c.xpc_connection_send_message(connection, reply);
//         c.xpc_release(reply);
//     }
// }.callback;
//
// pub fn handleXpcMessage(message: c.xpc_object_t, reply: c.xpc_object_t) void {
//     const command = c.xpc_dictionary_get_int64(message, "command");
//
//     if (command == null) {
//         c.xpc_dictionary_set_bool(reply, "success", false);
//         c.xpc_dictionary_set_string(reply, "error", "No command issued to Freetracer helper tool.");
//         return;
//     }
//
//     if (command == 101) {
//         print("\n:: Freetracer helper tool received command 101: {d}", .{command});
//     } else {
//         c.xpc_dictionary_set_bool(reply, "success", false);
//         c.xpc_dictionary_set_string(reply, "error", "Unknown command issued to Freetracer helper tool.");
//     }
// }
