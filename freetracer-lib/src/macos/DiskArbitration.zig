//! Disk Arbitration Framework Interface
//!
//! Provides high-level wrappers around macOS Disk Arbitration framework APIs
//! for safe and controlled management of storage devices. This module is used
//! by the privileged helper to validate and perform destructive operations
//! (unmount, eject) on target disks before data flashing.
//!
//! The Disk Arbitration framework provides:
//! - Device classification and metadata retrieval
//! - Safe mount/unmount operations with proper error handling
//! - Eject operations for removable media
//! - CFRunLoop integration for asynchronous operations
//!
//! Key Operations:
//! 1. Device Validation: Check if device is internal or removable
//! 2. Unmount: Safely unmount all volumes on a device
//! 3. Eject: Eject removable media (USB drives, SD cards, etc.)
//!
//! Safety Features:
//! - Prevents unmount/eject of internal devices (except SD card type)
//! - Validates device names and parameters
//! - Comprehensive error reporting with dissenter information
//! - Proper CFRunLoop handling for async operations

const std = @import("std");
const c = @import("../types.zig").c;
const DeviceType = @import("../types.zig").DeviceType;
const Debug = @import("../util/debug.zig");

// ============================================================================
// DEVICE VALIDATION - Inspect disk metadata and properties
// ============================================================================

/// Checks if the target disk is marked as an internal device by Disk Arbitration.
/// Internal devices typically include built-in storage (SSD, HDD), while external
/// devices include USB drives, SD cards, and other removable media.
///
/// `Arguments`:
///   diskDictionaryRef: CFDictionary obtained from DADiskCopyDescription()
///                      Contains device metadata and properties
///
/// `Returns`:
///   true if device is marked as internal, false if external/removable
///
/// `Errors`:
///   error.REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY
///     - Key not found in dictionary
///     - Value is not of type CFBoolean
pub fn isTargetDiskInternalDevice(diskDictionaryRef: c.CFDictionaryRef) !bool {
    const isInternalDeviceRef: c.CFBooleanRef = @ptrCast(c.CFDictionaryGetValue(diskDictionaryRef, c.kDADiskDescriptionDeviceInternalKey));

    if (isInternalDeviceRef == null or c.CFGetTypeID(isInternalDeviceRef) != c.CFBooleanGetTypeID()) {
        Debug.log(.ERROR, "Failed to obtain internal device key boolean.", .{});
        return error.REQUEST_DISK_UNMOUNT_FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY;
    }

    const isDeviceInternal: bool = (isInternalDeviceRef == c.kCFBooleanTrue);

    Debug.log(.INFO, "Finished checking for an internal device... isDeviceInternal: {any}", .{isDeviceInternal});

    return isDeviceInternal;
}

// ============================================================================
// UNMOUNT OPERATIONS - Safely unmount all volumes on a device
// ============================================================================

/// Safely unmounts all volumes on the specified BSD disk device.
/// Uses Disk Arbitration framework to coordinate unmount operations
/// with the system and other processes that may have the device in use.
///
/// This function blocks until the unmount operation completes (synchronous).
/// The unmount result is written to statusResultPtr via callback.
///
/// `Arguments`:
///   targetDisk: BSD device name (e.g., "disk2", "disk3s1")
///               Must be null-terminated and at least 2 characters long
///   deviceType: Device classification (SD, USB, Internal, etc.)
///               Used to validate unmount is appropriate for this device
///   statusResultPtr: Pointer to bool for unmount result
///                    Set to true on success, false on failure
///
/// `Side Effects`:
///   - Creates a DASession and schedules with current CFRunLoop
///   - Blocks execution while CFRunLoopRun() processes the callback
///   - Modifies value at statusResultPtr
///
/// `Errors`:
///   error.MALFORMED_TARGET_DISK_STRING: BSD name too short
///   error.FAILED_TO_CREATE_DA_SESSION: Could not create Disk Arbitration session
///   error.FAILED_TO_CREATE_DA_DISK_REF: Could not create disk reference
///   error.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF: Could not get disk metadata
///   error.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE: Attempted unmount of internal device
///
/// `TODO`:
///   - Refactor into smaller helper functions for better maintainability
pub fn requestUnmount(targetDisk: [:0]const u8, deviceType: DeviceType, statusResultPtr: *bool) !void {
    // Validate input: BSD names must be at least "dx" format
    if (targetDisk.len < 2) return error.MALFORMED_TARGET_DISK_STRING;

    const bsdName = std.mem.sliceTo(targetDisk, 0x00);
    Debug.log(.INFO, "Initiating unmount for: {s}", .{targetDisk});

    // Create a Disk Arbitration session for this operation
    // DASession is the entry point for all Disk Arbitration operations
    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);
    if (daSession == null) return error.FAILED_TO_CREATE_DA_SESSION;
    defer c.CFRelease(daSession);

    Debug.log(.INFO, "Successfully started a blank DASession.", .{});

    // Schedule the DASession with the current CFRunLoop
    // This allows the session to deliver callbacks through the run loop
    const currentLoop = c.CFRunLoopGetCurrent();
    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    Debug.log(.INFO, "DASession is successfully scheduled with the run loop.", .{});

    // Create a DADiskRef from the BSD device name
    // This reference represents the disk and its volumes
    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, bsdName.ptr);
    if (daDiskRef == null) return error.FAILED_TO_CREATE_DA_DISK_REF;
    defer c.CFRelease(daDiskRef);

    Debug.log(.INFO, "DA Disk refererence is successfuly created for the provided device BSD name.", .{});

    // Get device metadata as CFDictionary
    // Contains properties like whether device is internal, removable, etc.
    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));
    if (diskInfo == null) return error.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    defer c.CFRelease(diskInfo);

    Debug.log(.INFO, "DA Disk Description is successfully obtained/copied.", .{});

    // Safety check: prevent unmounting internal devices (except SD cards)
    // SD cards can be used internally in some Macs but should be treated as removable
    if (try isTargetDiskInternalDevice(diskInfo)) {
        if (deviceType != .SD) return error.UNMOUNT_REQUEST_ON_INTERNAL_DEVICE;
    }

    Debug.log(.INFO, "Unmount request passed checks. Initiating unmount call for disk: {s}.", .{bsdName});

    // Request unmount with kDADiskUnmountOptionWhole to unmount all volumes
    // Register callback to be invoked when operation completes
    // statusResultPtr will be modified by the callback
    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, @ptrCast(statusResultPtr));

    // Request unmount with kDADiskUnmountOptionWhole to unmount all volumes
    // Register callback to be invoked when operation completes
    // statusResultPtr will be modified by the callback
    c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionWhole, unmountDiskCallback, @ptrCast(statusResultPtr));

    // Block until the callback stops the run loop
    // This makes the operation appear synchronous to the caller
    c.CFRunLoopRun();
}

// ============================================================================
// EJECT OPERATIONS - Eject removable media devices
// ============================================================================

/// Ejects the specified BSD disk device using Disk Arbitration.
/// Eject is used for removable media (USB drives, SD cards) to safely
/// power down and disconnect the device from the system.
///
/// This function blocks until the eject operation completes (synchronous).
/// The eject result is written to statusResultPtr via callback.
///
/// `Arguments`:
///   targetDisk: BSD device name (e.g., "disk2", "disk3s1")
///               Must be null-terminated and at least 2 characters long
///   deviceType: Device classification (SD, USB, Internal, etc.)
///               Used to validate eject is appropriate for this device
///   statusResultPtr: Pointer to bool for eject result
///                    Set to true on success, false on failure
///
/// `Side Effects`:
///   - Creates a DASession and schedules with current CFRunLoop
///   - Blocks execution while CFRunLoopRun() processes the callback
///   - Modifies value at statusResultPtr
///
/// `Errors`:
///   error.MALFORMED_TARGET_DISK_STRING: BSD name too short
///   error.FAILED_TO_CREATE_DA_SESSION: Could not create Disk Arbitration session
///   error.FAILED_TO_CREATE_DA_DISK_REF: Could not create disk reference
///   error.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF: Could not get disk metadata
///   error.EJECT_REQUEST_ON_INTERNAL_DEVICE: Attempted eject of internal device
pub fn requestEject(targetDisk: [:0]const u8, deviceType: DeviceType, statusResultPtr: *bool) !void {
    // Validate input: BSD names must be at least "dx" format
    if (targetDisk.len < 2) return error.MALFORMED_TARGET_DISK_STRING;

    Debug.log(.INFO, "Received eject bsdName: {s}", .{targetDisk});

    // Create a Disk Arbitration session for this operation
    const daSession = c.DASessionCreate(c.kCFAllocatorDefault);
    if (daSession == null) return error.FAILED_TO_CREATE_DA_SESSION;
    defer c.CFRelease(daSession);

    // Schedule the DASession with the current CFRunLoop
    const currentLoop = c.CFRunLoopGetCurrent();
    c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);
    defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

    // Create a DADiskRef from the BSD device name
    const daDiskRef: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, targetDisk.ptr);
    if (daDiskRef == null) return error.FAILED_TO_CREATE_DA_DISK_REF;
    defer c.CFRelease(daDiskRef);

    // Get device metadata to validate device type
    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));
    if (diskInfo == null) return error.FAILED_TO_OBTAIN_DISK_INFO_DICT_REF;
    defer c.CFRelease(diskInfo);

    // Safety check: prevent ejecting internal devices (except SD cards)
    if (try isTargetDiskInternalDevice(diskInfo)) {
        if (deviceType != .SD) return error.EJECT_REQUEST_ON_INTERNAL_DEVICE;
    }

    Debug.log(.INFO, "Eject request passed checks. Initiating eject call for disk: {s}.", .{targetDisk});

    // Request eject with kDADiskEjectOptionDefault
    // Register callback to be invoked when operation completes
    c.DADiskEject(daDiskRef, c.kDADiskEjectOptionDefault, ejectDiskCallback, @ptrCast(statusResultPtr));

    // Block until the callback stops the run loop
    c.CFRunLoopRun();
}

// ============================================================================
// CALLBACK FUNCTIONS - C-convention callbacks for async Disk Arbitration ops
// ============================================================================

/// C-convention callback invoked by Disk Arbitration when unmount completes.
/// Called by CFRunLoop after DADiskUnmount() completes (success or failure).
/// Extracts result status and writes to context pointer (bool*).
///
/// `Arguments`:
///   disk: DADiskRef provided by Disk Arbitration (valid during callback)
///   dissenter: Non-null if another process dissented (prevented unmount)
///              Contains error status and descriptive message
///   context: User context pointer (void*), expects pointer to bool*
///            Receives unmount success/failure result
///
/// `Side Effects`:
///   - Modifies boolean value at context pointer
///   - Stops the current CFRunLoop to unblock requestUnmount()
///   - Logs operation result and any error information
///
/// `Notes`:
///   - Must use callconv(.c) for C calling convention compatibility
///   - Stops CFRunLoop to allow requestUnmount() to return
///   - Dissenter contains status code and human-readable error message
pub fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.c) void {
    // Validate context pointer was provided by requestUnmount()
    if (context == null) {
        Debug.log(.ERROR, "Unmount callback invoked without context pointer.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
        return;
    }

    const unmountStatus: *bool = @ptrCast(context);
    Debug.log(.INFO, "Processing unmountDiskCallback()...", .{});

    // Extract BSD device name from the DADiskRef
    const bsdNameCPtr: [*c]const u8 = c.DADiskGetBSDName(disk);
    const bsdName: [:0]const u8 = @ptrCast(std.mem.sliceTo(bsdNameCPtr, 0x00));

    if (bsdName.len == 0) {
        Debug.log(.WARNING, "unmountDiskCallback(): bsdName received is of 0 length.", .{});
    }

    // Check if a dissenter prevented the unmount operation
    // Dissenters are other processes that have the device in use
    if (dissenter != null) {
        Debug.log(.WARNING, "Disk Arbitration Dissenter returned a non-empty status.", .{});

        unmountStatus.* = false;

        // Extract error status and human-readable message from dissenter
        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusBuffer: [256:0]u8 = std.mem.zeroes([256:0]u8);
        var statusMessage: [:0]const u8 = "unavailable";

        // Convert CFString error message to Zig string
        if (statusStringRef != null) {
            const wroteCString = c.CFStringGetCString(statusStringRef, &statusBuffer, statusBuffer.len, c.kCFStringEncodingUTF8) != 0;
            if (wroteCString) statusMessage = statusBuffer[0..];
        }

        Debug.log(.ERROR, "Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusMessage });

        // Stop run loop to unblock requestUnmount()
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    } else {
        // Unmount succeeded - no dissenter
        unmountStatus.* = true;
        Debug.log(.INFO, "Successfully unmounted disk: {s}", .{bsdName});
        Debug.log(.INFO, "Finished unmounting all volumes for device.", .{});

        // Stop run loop to unblock requestUnmount()
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}

/// C-convention callback invoked by Disk Arbitration when eject completes.
/// Called by CFRunLoop after DADiskEject() completes (success or failure).
/// Extracts result status and writes to context pointer (bool*).
///
/// `Arguments`:
///   disk: DADiskRef provided by Disk Arbitration (valid during callback)
///   dissenter: Non-null if another process dissented (prevented eject)
///              Contains error status and descriptive message
///   context: User context pointer (void*), expects pointer to bool*
///            Receives eject success/failure result
///
/// `Side Effects`:
///   - Modifies boolean value at context pointer
///   - Stops the current CFRunLoop to unblock requestEject()
///   - Logs operation result and any error information
///
/// `Notes`:
///   - Must use callconv(.c) for C calling convention compatibility
///   - Stops CFRunLoop to allow requestEject() to return
///   - Dissenter contains status code and human-readable error message
pub fn ejectDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.c) void {
    // Validate context pointer was provided by requestEject()
    if (context == null) {
        Debug.log(.ERROR, "Eject callback invoked without context pointer.", .{});
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
        return;
    }

    const ejectStatus: *bool = @ptrCast(context);
    Debug.log(.INFO, "Processing ejectDiskCallback()...", .{});

    // Extract BSD device name from the DADiskRef
    const bsdNameCPtr: [*c]const u8 = c.DADiskGetBSDName(disk);
    const bsdName: [:0]const u8 = @ptrCast(std.mem.sliceTo(bsdNameCPtr, 0x00));

    if (bsdName.len == 0) {
        Debug.log(.WARNING, "ejectDiskCallback(): bsdName received is of 0 length.", .{});
    }

    // Check if a dissenter prevented the eject operation
    if (dissenter != null) {
        Debug.log(.WARNING, "Disk Arbitration Dissenter returned a non-empty status for eject.", .{});

        ejectStatus.* = false;

        // Extract error status and human-readable message from dissenter
        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusBuffer: [256:0]u8 = std.mem.zeroes([256:0]u8);
        var statusMessage: [:0]const u8 = "unavailable";

        // Convert CFString error message to Zig string
        if (statusStringRef != null) {
            const wroteCString = c.CFStringGetCString(statusStringRef, &statusBuffer, statusBuffer.len, c.kCFStringEncodingUTF8) != 0;
            if (wroteCString) statusMessage = statusBuffer[0..];
        }

        Debug.log(.ERROR, "Failed to eject {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusMessage });

        // Stop run loop to unblock requestEject()
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    } else {
        // Eject succeeded - no dissenter
        ejectStatus.* = true;
        Debug.log(.INFO, "Successfully ejected disk: {s}", .{bsdName});

        // Stop run loop to unblock requestEject()
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}
