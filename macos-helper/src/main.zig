const std = @import("std");
const env = @import("env.zig");

const print = std.debug.print;

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
});

const kUnmountDiskRequest: i32 = 101;
const kUnmountDiskResponse: i32 = 201;

pub fn main() !void {
    const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        env.BUNDLE_ID,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );
    defer _ = c.CFRelease(portNameRef);

    var messagePortContext: c.CFMessagePortContext = c.CFMessagePortContext{
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

    std.log.info("Freetracer Helper Tool started. Awaiting requests...", .{});

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

comptime {
    @export(@as([*:0]const u8, @ptrCast(env.INFO_PLIST)), .{ .name = "__info_plist", .section = "__TEXT,__info_plist", .visibility = .default, .linkage = .strong });
    @export(@as([*:0]const u8, @ptrCast(env.LAUNCHD_PLIST)), .{ .name = "__launchd_plist", .section = "__TEXT,__launchd_plist", .visibility = .default, .linkage = .strong });
}
