const std = @import("std");
const c = @import("../../lib/sys/system.zig").c;
const env = @import("../../env.zig");
const System = @import("../../lib/sys/system.zig");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

const k = freetracer_lib.k;
const HelperReturnCode = freetracer_lib.HelperReturnCode;
const HelperInstallCode = freetracer_lib.HelperInstallCode;
const HelperUnmountRequestCode = freetracer_lib.HelperUnmountRequestCode;
const HelperResponseCode = freetracer_lib.HelperResponseCode;

/// MacOS-only
/// Checks via the SMJobBless system daemon if the privileged helper tool is installed.
/// "Client"-side function, whereas Freetracer main process acts as the client for the Freetracer Privileged Tool
/// @Returns HelperInstallCode = enum(bool) { FAILURE: bool = false, SUCCESS: bool = true}
pub fn isHelperToolInstalled() HelperInstallCode {
    if (!System.isMac) return HelperInstallCode.FAILURE;

    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, env.HELPER_BUNDLE_ID, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(helperLabel);

    const smJobCopyDict = c.SMJobCopyDictionary(c.kSMDomainSystemLaunchd, helperLabel);

    if (smJobCopyDict == null) {
        Debug.log(.ERROR, "isHelperToolInstalled(): the SMJobCopyDictionary for helper tool is NULL. Helper tool is NOT installed.", .{});
        return HelperInstallCode.FAILURE;
    }

    defer _ = c.CFRelease(smJobCopyDict);

    Debug.log(.INFO, "isHelperToolInstalled(): Helper tool found, it appears to be installed.", .{});

    return HelperInstallCode.SUCCESS;
}

/// MacOS-only
/// Installs the privileged helper tool via MacOS' SMJobBless.
/// "Client"-side function, whereas Freetracer main process acts as the client for the Freetracer Privileged Tool
/// @Returns HelperInstallCode = enum(bool) { FAILURE: bool = false, SUCCESS: bool = true}
pub fn installPrivilegedHelperTool() HelperInstallCode {
    if (!System.isMac) return HelperInstallCode.FAILURE;

    var installStatus: c.Boolean = c.FALSE;

    Debug.log(.DEBUG, "Install Helper Tool: attempting to obtain initial (empty) authorization.", .{});

    var authRef: c.AuthorizationRef = undefined;

    var authStatus: c.OSStatus = c.AuthorizationCreate(k.NullAuthorizationRights, k.NullAuthorizationEnvironment, k.EmptyAuthotizationFlags, &authRef);
    defer _ = c.AuthorizationFree(authRef, c.kAuthorizationFlagDefaults);

    if (authStatus != c.errAuthorizationSuccess) {
        Debug.log(.ERROR, "Freetracer failed to obtain empty authorization in the process of installing its privileged helper tool. AuthStatus: {d}.", .{authStatus});
        authRef = null;
        return HelperInstallCode.FAILURE;
    }

    Debug.log(.DEBUG, "Install Helper Tool: successfully obtained an empty authorization.", .{});

    var authItem = c.AuthorizationItem{
        .name = c.kSMRightBlessPrivilegedHelper,
        .flags = k.EmptyAuthorizationItemFlags,
        .value = k.NullAuthorizationItemValue,
        .valueLength = k.ZeroAuthorizationItemValueLength,
    };

    const authRights: c.AuthorizationRights = .{ .count = 1, .items = &authItem };
    const authFlags: c.AuthorizationFlags = c.kAuthorizationFlagDefaults | c.kAuthorizationFlagInteractionAllowed | c.kAuthorizationFlagPreAuthorize | c.kAuthorizationFlagExtendRights;

    Debug.log(.DEBUG, "Install Helper Tool: attempting to copy authorization rights to authorization ref.", .{});

    authStatus = c.AuthorizationCopyRights(authRef, &authRights, k.NullAuthorizationEnvironment, authFlags, k.NullAuthorizationRights);

    if (authStatus != c.errAuthorizationSuccess) {
        Debug.log(.ERROR, "Freetracer failed to obtain specific authorization rights in the process of installing its privileged helper tool. AuthStatus: {d}.", .{authStatus});
        return HelperInstallCode.FAILURE;
    }

    Debug.log(.DEBUG, "Install Helper Tool: successfully copied auth rights; attempting to create a bundle id CFStringRef.", .{});

    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, env.HELPER_BUNDLE_ID, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(helperLabel);

    Debug.log(.DEBUG, "Install Helper Tool: successfully created a bundle id CFStringRef.", .{});

    var cfError: c.CFErrorRef = null;

    Debug.log(.DEBUG, "Install Helper Tool: launching SMJobBless call on the helper.", .{});

    installStatus = c.SMJobBless(c.kSMDomainSystemLaunchd, helperLabel, authRef, &cfError);

    Debug.log(.INFO, "Install Helper Tool: SMJobBless call completed without kernel panicking.", .{});

    if (installStatus != c.TRUE) {
        Debug.log(.ERROR, "Install Helper Tool: SMJobBless call failed, proceeding to attempt to analyze error.", .{});
        //
        if (cfError == null) {
            Debug.log(.ERROR, "Freetracer failed to install its privileged helper tool without any error status from SMJobBless.", .{});
            return HelperInstallCode.FAILURE;
        }

        defer _ = c.CFRelease(cfError);

        // ERROR level in log is preserved intentionally to allow a full error trace in error-only severity reporting mode
        Debug.log(.ERROR, "Install Helper Tool: attempting to copy error description.", .{});

        const errorDesc = c.CFErrorCopyDescription(cfError);

        if (errorDesc == null) {
            Debug.log(.ERROR, "Freetracer could not copy error description from the SMJobBless operation error, error description is null.", .{});
            return HelperInstallCode.FAILURE;
        }

        // ERROR level in log is preserved intentionally to allow a full error trace in error-only severity reporting mode
        Debug.log(.ERROR, "Install Helper Tool: obtained a copy of error description.", .{});

        defer _ = c.CFRelease(errorDesc);

        // ERROR level in log is preserved intentionally to allow a full error trace in error-only severity reporting mode
        Debug.log(.ERROR, "Install Helper Tool: attempting to obtain a string from error description.", .{});

        var errDescBuffer: [512]u8 = undefined;
        const obtainErrorDescStatus = c.CFStringGetCString(errorDesc, &errDescBuffer, errDescBuffer.len, c.kCFStringEncodingUTF8);

        if (obtainErrorDescStatus == 0) {
            Debug.log(.ERROR, "Freetracer could not obtain error description from the SMJobBless operation error, error description is NOT null.", .{});
            return HelperInstallCode.FAILURE;
        }

        Debug.log(.ERROR, "Freetracer received SMJobBless error: {s}.", .{std.mem.sliceTo(&errDescBuffer, 0)});
        return HelperInstallCode.FAILURE;
    }

    if (installStatus == c.TRUE) {
        Debug.log(.INFO, "Freetracer successfully installed its privileged helper tool.", .{});
        return HelperInstallCode.SUCCESS;
    }

    Debug.log(.ERROR, "installPrivilegedHelperTool(): CRITICAL ERROR: Unreachable path reached! o_O", .{});
    unreachable;
}

pub fn requestHelperVersion() [:0]const u8 {
    if (!System.isMac) return HelperResponseCode.FAILURE;

    // Create a CString from the Privileged Tool's Apple App Bundle ID
    const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        env.HELPER_BUNDLE_ID,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );
    defer _ = c.CFRelease(portNameRef);

    const remoteMessagePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, portNameRef);

    if (remoteMessagePort == null) {
        Debug.log(.ERROR, "Freetracer unable to create a remote message port to Freetracer Helper Tool.", .{});
        return HelperResponseCode.FAILURE;
    }

    defer _ = c.CFRelease(remoteMessagePort);

    const dataPayload: [*c]const u8 = null;
    const dataLength: i32 = 0;

    const requestDataRef: c.CFDataRef = c.CFDataCreate(c.kCFAllocatorDefault, dataPayload, dataLength);
    defer _ = c.CFRelease(requestDataRef);

    var portResponseCode: c.SInt32 = 0;
    var responseData: c.CFDataRef = null;

    portResponseCode = c.CFMessagePortSendRequest(
        remoteMessagePort,
        k.HelperVersionRequest,
        requestDataRef,
        k.SendTimeoutInSeconds,
        k.ReceiveTimeoutInSeconds,
        c.kCFRunLoopDefaultMode,
        &responseData,
    );

    // TODO: Is the responseData == null check effective here?
    if (portResponseCode != c.kCFMessagePortSuccess or responseData == null) {
        Debug.log(
            .ERROR,
            "Freetracer failed to communicate with Freetracer Helper Tool - received invalid response code ({d}) or null response data ({any})",
            .{ portResponseCode, responseData },
        );
        return HelperResponseCode.FAILURE;
    }

    var result: [:0]const u8 = undefined;

    if (c.CFDataGetLength(responseData) >= 1) {
        const dataPtr = c.CFDataGetBytePtr(responseData);
        result = @ptrCast(@alignCast(dataPtr));
    }

    if (result.len < 1) {
        Debug.log(.ERROR, "Freetracer failed to receive a structured response from Freetracer Helper Tool: {s}.", .{result});
        return HelperResponseCode.FAILURE;
    }

    Debug.log(.INFO, "Freetracer successfully received response from Freetracer Helper Tool: {s}", .{result});

    return result;
}

/// MacOS-only
/// Sends a CFMessage to the Privileged Helper Tool via a CFPort to request a disk unmount
/// "Client"-side function, whereas Freetracer acts as the client for the Freetracer Privileged Tool
/// @Returns HelperUnmountRequestCode = enum(bool) { FAILURE: bool = false, SUCCESS: bool = true}
pub fn requestPerformUnmount(targetDisk: []const u8) HelperUnmountRequestCode {
    if (!System.isMac) return HelperUnmountRequestCode.FAILURE;

    // Create a CString from the Privileged Tool's Apple App Bundle ID
    const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        env.HELPER_BUNDLE_ID,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );
    defer _ = c.CFRelease(portNameRef);

    const remoteMessagePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, portNameRef);

    if (remoteMessagePort == null) {
        Debug.log(.ERROR, "Freetracer unable to create a remote message port to Freetracer Helper Tool.", .{});
        return HelperUnmountRequestCode.FAILURE;
    }

    defer _ = c.CFRelease(remoteMessagePort);

    const dataPayload: [*c]const u8 = @ptrCast(targetDisk);
    const dataLength: i32 = @intCast(targetDisk.len);

    const requestDataRef: c.CFDataRef = c.CFDataCreate(c.kCFAllocatorDefault, dataPayload, dataLength);
    defer _ = c.CFRelease(requestDataRef);

    var helperResponseCode: c.SInt32 = 0;
    var responseData: c.CFDataRef = null;

    helperResponseCode = c.CFMessagePortSendRequest(
        remoteMessagePort,
        k.UnmountDiskRequest,
        requestDataRef,
        k.SendTimeoutInSeconds,
        k.ReceiveTimeoutInSeconds,
        c.kCFRunLoopDefaultMode,
        &responseData,
    );

    // TODO: Is the responseData == null check effective here?
    if (helperResponseCode != c.kCFMessagePortSuccess or responseData == null) {
        Debug.log(
            .ERROR,
            "Freetracer failed to communicate with Freetracer Helper Tool - received invalid response code ({d}) or null response data ({any})",
            .{ helperResponseCode, responseData },
        );
        return HelperUnmountRequestCode.FAILURE;
    }

    var result: i32 = -1;

    if (c.CFDataGetLength(responseData) >= @sizeOf(i32)) {
        const dataPtr = c.CFDataGetBytePtr(responseData);
        const resultPtr: *const i32 = @ptrCast(@alignCast(dataPtr));
        result = resultPtr.*;
    }

    if (result != @as(i32, @intFromEnum(HelperReturnCode.SUCCESS))) {
        // if (result != 40) {
        Debug.log(.ERROR, "Freetracer failed to receive a structured response from Freetracer Helper Tool: {d}.", .{result});
        return HelperUnmountRequestCode.FAILURE;
    }

    Debug.log(.INFO, "Freetracer successfully received response from Freetracer Helper Tool: {d}", .{result});

    return HelperUnmountRequestCode.SUCCESS;
}
