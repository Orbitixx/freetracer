const std = @import("std");
const env = @import("env.zig");

const print = std.std.log.err;

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("DiskArbitration/DiskArbitration.h");
});

const kUnmountDiskRequest: i32 = 101;
const kUnmountDiskResponse: i32 = 201;

var queuedUnmounts: i32 = 0;

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

/// Runs once for every CFMessage received from the Freetracer tool
pub fn messagePortCallback(port: c.CFMessagePortRef, msgId: c.SInt32, data: c.CFDataRef, info: ?*anyopaque) callconv(.C) c.CFDataRef {
    var returnData: c.CFDataRef = null;

    _ = port;
    _ = info;

    var requestData: ?[*c]const u8 = null;
    var requestLength: usize = 0;
    var response: i32 = -1;

    if (data != null) {
        requestData = c.CFDataGetBytePtr(data);
        requestLength = @intCast(c.CFDataGetLength(data));

        if (requestData != null and requestLength > 0) {
            std.log.info("Request data received: {s}\n", .{std.mem.sliceTo(requestData.?, 0)});
        }
    }

    switch (msgId) {
        kUnmountDiskRequest => {
            std.log.info("Freetracer Helper Tool received DADiskUnmount() request {d}.", .{kUnmountDiskRequest});
            if (requestData != null) {
                // const payload: []const u8 = @ptrCast(requestData.?);
                response = @intFromEnum(processDiskUnmountRequest(std.mem.sliceTo(requestData.?, 0)));
            }
        },
        else => {
            std.log.warn("WARNING: Freetracer Helper Tool received unknown request. Aborting repsponse...", .{});
        },
    }

    const responseBytePtr: [*c]const u8 = @ptrCast(&response);

    returnData = c.CFDataCreate(c.kCFAllocatorDefault, responseBytePtr, @sizeOf(i32));

    std.log.info("Freetracer Helper Tool successfully packaged response: {d}.", .{response});
    return returnData;
}

pub fn processDiskUnmountRequest(bsdName: []const u8) ReturnCode {
    std.log.info("Received bsdName: {s}", .{bsdName});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) {
        std.log.err("Error: Failed to create DASession\n", .{});
        return ReturnCode.FAILED_TO_CREATE_DA_SESSION;
    }
    defer _ = c.CFRelease(daSession);

    const currentLoop = c.CFRunLoopGetCurrent();

    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    // Ensure unscheduling happens before the session is released
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, bsdName.ptr);

    if (daDiskRef == null) {
        std.log.err("\nError: Could not create DADiskRef for '{s}', skipping.\n", .{bsdName});
        return ReturnCode.FAILED_TO_CREATE_DA_DISK_REF;
    }
    defer _ = c.CFRelease(daDiskRef);

    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));

    if (diskInfo == null) return ReturnCode.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    defer _ = c.CFRelease(diskInfo);

    // _ = c.CFShow(diskInfo);

    // --- @PROP: Check for EFI parition ---------------------------------------------------
    // Do not release efiKey, release causes segmentation fault
    const efiKeyRef: c.CFStringRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionVolumeNameKey));

    var efiKeyBuf: [128]u8 = undefined;
    _ = c.CFStringGetCString(efiKeyRef, &efiKeyBuf, efiKeyBuf.len, c.kCFStringEncodingUTF8);

    if (efiKeyRef == null or c.CFGetTypeID(efiKeyRef) != c.CFStringGetTypeID()) {
        return ReturnCode.FAILED_TO_OBTAIN_EFI_KEY_STRING;
    }

    const isEfi = std.mem.count(u8, &efiKeyBuf, "EFI") > 0;
    // --- @ENDPROP: EFI

    // --- @PROP: Check for DeviceInternal ---------------------------------------------------
    const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionDeviceInternalKey));

    if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
        return ReturnCode.FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY_BOOL;
    }

    const isInternalDevice: bool = (isInternalDeviceRef == c.kCFBooleanTrue);
    // --- @ENDPROP: DeviceInternal

    if (isInternalDevice) {
        std.log.err("\nERROR: internal device detected on disk: {s}. Aborting unmount operations for device.", .{bsdName});
        return ReturnCode.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;
    }

    if (isEfi) {
        std.log.warn("\nWARNING: Skipping unmount because of a potential EFI partition on disk: {s}.", .{bsdName});
        return ReturnCode.SKIPPED_UNMOUNT_ATTEMPT_ON_EFI_PARTITION;
    }

    std.log.info("\nUnmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionDefault, unmountDiskCallback, &queuedUnmounts);

    queuedUnmounts += 1;

    if (queuedUnmounts > 0) {
        c.CFRunLoopRun();
    } else {
        std.log.err("\nERROR: No valid unmount calls could be initiated for device: {s}.", .{bsdName});
    }

    return ReturnCode.SUCCESS;
}

fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    _ = context;
    // if (context == null) {
    //     std.log.err("\nERROR: Unmount callback returned NULL context.");
    //     return;
    // }

    // const counter_ptr: *u8 = @ptrCast(context);
    // _ = context;
    const bsdName = if (c.DADiskGetBSDName(disk)) |name| std.mem.sliceTo(name, 0) else "Unknown Disk";

    if (dissenter != null) {
        std.log.err("\nWARNING: Disk Arbitration Dissenter returned a non-empty status.", .{});

        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusString: [256]u8 = undefined;

        if (statusStringRef != null) {
            _ = c.CFStringGetCString(statusStringRef, &statusString, statusString.len, c.kCFStringEncodingUTF8);
        }
        std.log.err("\nERROR: Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusString });
    } else {
        std.log.err("\nSuccessfully unmounted disk: {s}", .{bsdName});
        queuedUnmounts -= 1;
    }

    if (queuedUnmounts == 0) {
        std.log.info("\nFinished unmounting all volumes for device.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}

pub const ReturnCode = enum(i32) {
    SUCCESS = 0,
    FAILED_TO_CREATE_DA_SESSION = 4000,
    FAILED_TO_CREATE_DA_DISK_REF = 4001,
    FAILED_TO_OBTAIN_DISK_INFO_DICT_REF = 4002,
    FAILED_TO_OBTAIN_EFI_KEY_STRING = 4003,
    FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY_BOOL = 4004,
    UNMOUNT_REQUEST_ON_INTERNAL_DEVICE = 4005,
    SKIPPED_UNMOUNT_ATTEMPT_ON_EFI_PARTITION = 4006,
};

comptime {
    @export(@as([*:0]const u8, @ptrCast(env.INFO_PLIST)), .{ .name = "__info_plist", .section = "__TEXT,__info_plist", .visibility = .default, .linkage = .strong });
    @export(@as([*:0]const u8, @ptrCast(env.LAUNCHD_PLIST)), .{ .name = "__launchd_plist", .section = "__TEXT,__launchd_plist", .visibility = .default, .linkage = .strong });
}
