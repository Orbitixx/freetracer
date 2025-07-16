const std = @import("std");
const env = @import("env.zig");

const freetracer_lib = @import("freetracer-lib");

const Debug = freetracer_lib.Debug;

const k = freetracer_lib.k;
const c = freetracer_lib.c;

const MachCommunicator = freetracer_lib.MachCommunicator;

const ReturnCode = freetracer_lib.HelperReturnCode;
const SerializedData = freetracer_lib.SerializedData;
const WriteRequestData = freetracer_lib.WriteRequestData;

var queuedUnmounts: i32 = 0;

pub const WRITE_BLOCK_SIZE = 4096;

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    defer {
        _ = debugAllocator.detectLeaks();
        _ = debugAllocator.deinit();
    }

    // Initialize Debug singleton
    try Debug.init(allocator, .{});
    defer Debug.deinit();

    Debug.log(.DEBUG, "Debug logger initialized.", .{});

    var machCommunicator = MachCommunicator.init(allocator, .{
        .bundleId = env.BUNDLE_ID,
        .ownerName = "Freetracer Helper Tool",
        .processMessageFn = processRequestMessage,
    });

    try machCommunicator.start();
    defer machCommunicator.deinit();
}

fn processRequestMessage(msgId: i32, requestData: SerializedData) !SerializedData {
    var responseData: SerializedData = undefined;

    switch (msgId) {
        //
        k.HelperVersionRequest => {
            Debug.log(.INFO, "Freetracer Helper Tool received a version query request [{d}].", .{k.HelperVersionRequest});

            const versionString = handleHelperVersionCheckRequest();
            responseData = SerializedData.serialize([:0]const u8, @ptrCast(versionString));
        },

        k.UnmountDiskRequest => {
            Debug.log(.INFO, "Freetracer Helper Tool received DADiskUnmount() request [{d}].", .{k.UnmountDiskRequest});

            const responseCode = handleDiskUnmountRequest(requestData);

            Debug.log(.WARNING, "responseCode is: {d}", .{@intFromEnum(responseCode)});

            responseData = SerializedData.serialize(ReturnCode, responseCode);
        },

        k.WriteISOToDeviceRequest => {
            Debug.log(.INFO, "Freetracer Helper Tool received WriteISOToDeviceRequest [{d}].", .{k.WriteISOToDeviceRequest});

            const responseCode = handleWriteISOToDeviceRequest(requestData);
            responseData = SerializedData.serialize(ReturnCode, responseCode);
        },

        else => {
            Debug.log(.WARNING, "Freetracer Helper Tool received unknown request: {d}. Ignoring request...", .{msgId});
        },
    }

    return responseData;
}

fn handleHelperVersionCheckRequest() [:0]const u8 {
    return @ptrCast(env.HELPER_VERSION);
}

fn handleDiskUnmountRequest(requestData: SerializedData) ReturnCode {
    const bsdName = std.mem.sliceTo(&requestData.data, 0x00);
    // const bsdName = std.mem.sliceTo(dataSlice, 0x00);

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

fn handleWriteISOToDeviceRequest(requestData: SerializedData) ReturnCode {
    const data: WriteRequestData = SerializedData.deserialize(WriteRequestData, requestData);

    // TODO: launch on its own thread, such that the main thread may respond to status requests
    writeISO(data.isoPath, data.devicePath) catch |err| {
        Debug.log(.ERROR, "Unable to write to device. Error: {any}", .{err});
        return ReturnCode.FAILED_TO_WRITE_ISO_TO_DEVICE;
    };

    return ReturnCode.SUCCESS;
}

fn writeISO(isoPath: []const u8, devicePath: []const u8) !void {
    Debug.log(.DEBUG, "Begin writing prep...", .{});
    var writeBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const isoFile: std.fs.File = try std.fs.cwd().openFile(isoPath, .{ .mode = .read_only });
    defer isoFile.close();

    const device = try std.fs.openFileAbsolute(devicePath, .{ .mode = .read_write });
    defer device.close();

    const fileStat = try isoFile.stat();
    const ISO_SIZE = fileStat.size;

    defer Debug.log(.INFO, "Write finished executing...", .{});

    var currentByte: u64 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{ISO_SIZE});

    Debug.log(.INFO, "Writing ISO to device, please wait...", .{});

    while (currentByte < ISO_SIZE) {
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
    }

    try device.sync();

    Debug.log(.INFO, "Finished writing ISO image to device!", .{});
}

comptime {
    @export(@as([*:0]const u8, @ptrCast(env.INFO_PLIST)), .{ .name = "__info_plist", .section = "__TEXT,__info_plist", .visibility = .default, .linkage = .strong });
    @export(@as([*:0]const u8, @ptrCast(env.LAUNCHD_PLIST)), .{ .name = "__launchd_plist", .section = "__TEXT,__launchd_plist", .visibility = .default, .linkage = .strong });
}
