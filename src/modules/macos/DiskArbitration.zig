const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const c = @import("../../lib/sys/system.zig").c;

const MacOS = @import("MacOSTypes.zig");
const toSlice = @import("IOKit.zig").toSlice;

const IOMediaVolume = MacOS.IOMediaVolume;
const USBDevice = MacOS.USBDevice;
const USBStorageDevice = MacOS.USBStorageDevice;

pub fn unmountAllVolumes(pDevice: *const USBStorageDevice) !void {
    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

    if (daSession == null) {
        debug.print("ERROR: Failed to create DASession\n");
        return error.DAFailedToCreateDiskArbitrationSession;
    }
    defer _ = c.CFRelease(daSession);

    const currentLoop = c.CFRunLoopGetCurrent();

    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);
    // Ensure unscheduling happens before session is released
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    var queuedUnmounts: u8 = 0;

    for (pDevice.*.volumes.items) |volume| {
        const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, volume.bsdName.ptr);

        debug.printf("\nRetrieving details for disk: '{s}'.", .{volume.bsdName});

        if (daDiskRef == null) {
            debug.printf("\nWARNING: Could not create DADiskRef for '{s}', skipping.\n", .{volume.bsdName});
            continue;
        }
        defer _ = c.CFRelease(daDiskRef);

        const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));

        if (diskInfo == null) return error.DAFailedToObtainADiskInfoDictionaryRef;
        defer _ = c.CFRelease(diskInfo);

        // _ = c.CFShow(diskInfo);

        //  TODO: Other important keys to check:
        // [ ] VolumePath == "/"
        // [x] DeviceInternal == true

        // --- @PROP: Check for EFI parition ---------------------------------------------------
        // Do not release efiKey, release causes segmentation fault
        const efiKeyRef: c.CFStringRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionVolumeNameKey));

        var efiKeyBuf: [128]u8 = undefined;
        _ = c.CFStringGetCString(efiKeyRef, &efiKeyBuf, efiKeyBuf.len, c.kCFStringEncodingUTF8);

        if (efiKeyRef == null or c.CFGetTypeID(efiKeyRef) != c.CFStringGetTypeID()) {
            return error.DAFailedToObtainEFIKeyCFString;
        }

        const isEfi = std.mem.count(u8, &efiKeyBuf, "EFI") > 0;
        // --- @ENDPROP: EFI

        // --- @PROP: Check for DeviceInternal ---------------------------------------------------
        const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionDeviceInternalKey));

        if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
            return error.DAFailedToObtainInternalDeviceCFBoolean;
        }

        const isInternalDevice: bool = (isInternalDeviceRef == c.kCFBooleanTrue);
        // --- @ENDPROP: DeviceInternal

        if (isInternalDevice) {
            debug.printf("\nERROR: internal device detected on disk: {s}. Aborting unmount operations for device.", .{volume.bsdName});
            return error.DAUnmountCalledOnInternalDevice;
        }

        if (isEfi) {
            debug.printf("\nWARNING: Skipping unmount because of a potential EFI partition on disk: {s}.", .{volume.bsdName});
            continue;
        }

        debug.printf("\nInitiating unmount call for disk: {s}", .{volume.bsdName});

        queuedUnmounts += 1;

        c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionDefault, unmountDiskCallback, &queuedUnmounts);
    }

    if (queuedUnmounts > 0) {
        c.CFRunLoopRun();
    } else {
        debug.printf("\nERROR: No valid unmount calls could be initiated for device: {s}.", .{pDevice.*.bsdName});
    }
}

fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    if (context == null) {
        debug.print("\nERROR: Unmount callback returned NULL context.");
        return;
    }

    const counter_ptr: *u8 = @ptrCast(context);
    // _ = context;
    const bsdName = if (c.DADiskGetBSDName(disk)) |name| toSlice(name) else "Unknown Disk";
    if (dissenter != null) {
        debug.print("\nWARNING: Disk Arbitration Dissenter returned a non-empty status.");

        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusString: [256]u8 = undefined;

        if (statusStringRef != null) {
            _ = c.CFStringGetCString(statusStringRef, &statusString, statusString.len, c.kCFStringEncodingUTF8);
        }
        debug.printf("\nERROR: Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusString });
    } else {
        debug.printf("\nSuccessfully unmounted disk: {s}", .{bsdName});
        counter_ptr.* -= 1;
    }

    if (counter_ptr.* == 0) {
        debug.print("\nSuccessfully unmounted all volumes for device.");
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}
