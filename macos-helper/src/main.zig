const std = @import("std");
const env = @import("env.zig");
const time = @import("lib/time.zig");
const shared = @import("lib/shared.zig");

// Constants struct in MacOS' format
const k = shared.k;
const ReturnCode = shared.HelperReturnCode;

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("DiskArbitration/DiskArbitration.h");
});

var queuedUnmounts: i32 = 0;

pub const Debug = struct {
    var instance: ?Logger = null;

    pub const SeverityLevel = enum(u8) {
        DEBUG,
        INFO,
        WARNING,
        ERROR,
    };

    pub fn log(comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
        if (instance) |*inst| {
            inst.log(level, fmt, args);
        }
    }

    pub const Logger = struct {
        allocator: std.mem.Allocator,

        pub fn log(self: *Logger, comptime level: SeverityLevel, comptime fmt: []const u8, args: anytype) void {
            const t = time.now();

            comptime var logFn: ?*const fn (comptime format: []const u8, args: anytype) void = null;
            comptime var severityPrefix: [:0]const u8 = "NONE";

            switch (level) {
                .DEBUG => {
                    logFn = std.log.debug;
                    severityPrefix = "DEBUG";
                },
                .INFO => {
                    logFn = std.log.info;
                    severityPrefix = "INFO";
                },
                .WARNING => {
                    logFn = std.log.warn;
                    severityPrefix = "WARNING";
                },
                .ERROR => {
                    logFn = std.log.err;
                    severityPrefix = "ERROR";
                },
            }

            // Create the full message with timestamp and format arguments
            const full_message = std.fmt.allocPrintZ(self.allocator, "[{d:0>2}/{d:0>2}/{d} {d:0>2}:{d:0>2}:{d:0>2}] {s}: " ++ fmt, .{
                t.month,
                t.day,
                t.year,
                t.hours,
                t.minutes,
                t.seconds,
                severityPrefix,
            } ++ args) catch |err| blk: {
                const msg = "\nlogError(): ERROR occurred attempting to allocPrintZ msg: \n\t{s}\nError: {any}";
                std.debug.print(msg, .{ fmt, err });
                Debug.log(.ERROR, msg, .{ fmt, err });
                break :blk "";
            };

            defer self.allocator.free(full_message);

            if (full_message.len < 1) return;

            //std.debug.print("{s}", .{full_message});

            if (logFn) |log_fn| {
                log_fn("{s}", .{full_message});
            }
        }
    };
};

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    defer {
        _ = debugAllocator.detectLeaks();
        _ = debugAllocator.deinit();
    }

    // Initialize Debug singleton
    Debug.instance = Debug.Logger{ .allocator = allocator };
    Debug.log(.DEBUG, "Debug logger initialized.", .{});

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
        Debug.log(.ERROR, "Freetracer Helper Tool unable to create a local message port.", .{});
        return;
    }

    defer _ = c.CFRelease(localMessagePort);

    const kRunLoopOrder: c.CFIndex = 0;

    const runLoopSource: c.CFRunLoopSourceRef = c.CFMessagePortCreateRunLoopSource(c.kCFAllocatorDefault, localMessagePort, kRunLoopOrder);
    defer _ = c.CFRelease(runLoopSource);

    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), runLoopSource, c.kCFRunLoopDefaultMode);
    defer c.CFRunLoopSourceInvalidate(runLoopSource);

    Debug.log(.INFO, "Freetracer Helper Tool started. Awaiting requests...", .{});

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

    if (data == null) {
        Debug.log(.WARNING, "messagePortCallback received NULL data as parameter. Ignoring request...", .{});
        return returnData;
    }

    requestData = c.CFDataGetBytePtr(data);
    requestLength = @intCast(c.CFDataGetLength(data));

    if (requestData == null) {
        Debug.log(.WARNING, "The received request data is NULL. Ignoring request...", .{});
        return returnData;
    }

    if (requestLength < 1) {
        Debug.log(.WARNING, "The received length of the request data is 0.", .{});
        return returnData;
    }

    // Data capture, not a conditional. Data check conditionals must have already passed by this point.
    if (requestData) |rdata| {
        Debug.log(.INFO, "Request data received: {s}\n", .{std.mem.sliceTo(rdata, 0x00)});
    }

    switch (msgId) {
        k.UnmountDiskRequest => {
            Debug.log(.INFO, "Freetracer Helper Tool received DADiskUnmount() request {d}.", .{k.UnmountDiskRequest});

            if (requestData) |rdata| {
                response = @intFromEnum(processDiskUnmountRequest(std.mem.sliceTo(rdata, 0x00)));
            } else {
                Debug.log(.WARNING, "Freetracer Helper Tool received a NULL request data in the UnmoutDiskRequest message. Request ignored.", .{});
            }
        },
        else => {
            Debug.log(.WARNING, "Freetracer Helper Tool received unknown request. Ignoring response...", .{});
        },
    }

    const responseBytePtr: [*c]const u8 = @ptrCast(&response);

    returnData = c.CFDataCreate(c.kCFAllocatorDefault, responseBytePtr, @sizeOf(i32));

    Debug.log(.INFO, "Freetracer Helper Tool successfully packaged response: {d}.", .{response});
    return returnData;
}

pub fn processDiskUnmountRequest(bsdName: []const u8) ReturnCode {
    Debug.log(.INFO, "Received bsdName: {s}", .{bsdName});

    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) {
        Debug.log(.ERROR, "Failed to create DASession\n", .{});
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
        return ReturnCode.FAILED_TO_CREATE_DA_DISK_REF;
    }
    defer _ = c.CFRelease(daDiskRef);

    Debug.log(.INFO, "DA Disk refererence is successfuly created for the provided device BSD name.", .{});

    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));

    if (diskInfo == null) return ReturnCode.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    defer _ = c.CFRelease(diskInfo);

    Debug.log(.INFO, "DA Disk Description is successfully obtained/copied.", .{});

    _ = c.CFShow(diskInfo);

    // NOTE: Not sure that it is appropriate to run an EFI check against a whole device, instead of a leaf.
    // Probably no value in doing so, unless the unmount is processed separately for each leaf volume.
    //
    // Debug.log(.DEBUG, "Running a check for an EFI partition...", .{});
    //
    // // --- @PROP: Check for EFI parition ---------------------------------------------------
    // // Do not release efiKey, release causes segmentation fault
    // const efiKeyRef: c.CFStringRef = @ptrCast(@alignCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionVolumeNameKey)));
    //
    // if (efiKeyRef == null) return ReturnCode.FAILED_TO_OBTAIN_EFI_KEY_STRING;
    //
    // std.log.info("\nEfi Key String: {any}", .{efiKeyRef});
    //
    // Debug.log(.DEBUG, "First intermediate EFI check log", .{});
    //
    // var efiKeyBuf: [255]u8 = std.mem.zeroes([255]u8);
    // const efiKeyResult: c.Boolean = c.CFStringGetCString(efiKeyRef, &efiKeyBuf, efiKeyBuf.len, c.kCFStringEncodingUTF8);
    //
    // if (efiKeyResult == 0 or efiKeyRef == null or c.CFGetTypeID(efiKeyRef) != c.CFStringGetTypeID()) {
    //     return ReturnCode.FAILED_TO_OBTAIN_EFI_KEY_STRING;
    // }
    //
    // Debug.log(.DEBUG, "Second intermediate EFI check log", .{});
    //
    // const isEfi = std.mem.count(u8, &efiKeyBuf, "EFI") > 0;
    // // --- @ENDPROP: EFI
    //
    // Debug.log(.INFO, "Finished checking for an EFI partition... Checking if the device is an internal device...", .{});

    // --- @PROP: Check for DeviceInternal ---------------------------------------------------
    const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionDeviceInternalKey));

    if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
        return ReturnCode.FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY_BOOL;
    }

    const isInternalDevice: bool = (isInternalDeviceRef == c.kCFBooleanTrue);
    // --- @ENDPROP: DeviceInternal

    Debug.log(.INFO, "Finished checking for an internal device...", .{});

    if (isInternalDevice) {
        Debug.log(.ERROR, "ERROR: internal device detected on disk: {s}. Aborting unmount operations for device.", .{bsdName});
        return ReturnCode.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;
    }

    // if (isEfi) {
    //     std.log.warn("Skipping unmount because of a potential EFI partition on disk: {s}.", .{bsdName});
    //     return ReturnCode.SKIPPED_UNMOUNT_ATTEMPT_ON_EFI_PARTITION;
    // }

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, &queuedUnmounts);

    queuedUnmounts += 1;

    if (queuedUnmounts > 0) {
        c.CFRunLoopRun();
    } else {
        Debug.log(.ERROR, "No valid unmount calls could be initiated for device: {s}.", .{bsdName});
    }

    return ReturnCode.SUCCESS;
}

fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    _ = context;
    // if (context == null) {
    //     Debug.log(.ERROR, "\nERROR: Unmount callback returned NULL context.");
    //     return;
    // }

    // const counter_ptr: *u8 = @ptrCast(context);
    // _ = context;

    // const bsdName = if (c.DADiskGetBSDName(disk)) |name| std.mem.sliceTo(name, 0) else "Unknown Disk";

    Debug.log(.INFO, "Processing unmountDiskCallback()...", .{});

    const bsdNameCPtr = c.DADiskGetBSDName(disk);

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
        queuedUnmounts -= 1;
    }

    if (queuedUnmounts == 0) {
        Debug.log(.INFO, "Finished unmounting all volumes for device.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}

comptime {
    @export(@as([*:0]const u8, @ptrCast(env.INFO_PLIST)), .{ .name = "__info_plist", .section = "__TEXT,__info_plist", .visibility = .default, .linkage = .strong });
    @export(@as([*:0]const u8, @ptrCast(env.LAUNCHD_PLIST)), .{ .name = "__launchd_plist", .section = "__TEXT,__launchd_plist", .visibility = .default, .linkage = .strong });
}
