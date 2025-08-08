const std = @import("std");
const env = @import("../../env.zig");
const System = @import("../../lib/sys/system.zig");

const freetracer_lib = @import("freetracer-lib");

const c = freetracer_lib.c;

const k = freetracer_lib.k;
const Debug = freetracer_lib.Debug;

const SerializedData = freetracer_lib.SerializedData;
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

// fn sendMachMessageToRemote(comptime requestType: type, requestData: requestType, msgId: i32, comptime returnType: type) !returnType {
//     if (!System.isMac) return error.CallAllowedOnMacOSOnly;
//
//     // Create a CString from the Privileged Tool's Apple App Bundle ID
//     const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
//         c.kCFAllocatorDefault,
//         env.HELPER_BUNDLE_ID,
//         c.kCFStringEncodingUTF8,
//         c.kCFAllocatorNull,
//     );
//     defer _ = c.CFRelease(portNameRef);
//
//     const remoteMessagePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, portNameRef);
//
//     if (remoteMessagePort == null) {
//         Debug.log(.ERROR, "Freetracer unable to create a remote message port to Freetracer Helper Tool.", .{});
//         return error.UnableToCreateRemoteMessagePort;
//     }
//
//     defer _ = c.CFRelease(remoteMessagePort);
//
//     const s_requestData = try SerializedData.serialize(requestType, requestData);
//
//     const requestDataRef: c.CFDataRef = @ptrCast(s_requestData.constructCFDataRef());
//     defer _ = c.CFRelease(requestDataRef);
//
//     var responseDataRef: c.CFDataRef = null;
//     var helperResponseCode: c.SInt32 = 0;
//
//     Debug.log(.INFO, "Freetracer is preparing to send request to Privileged Helper Tool...", .{});
//
//     helperResponseCode = c.CFMessagePortSendRequest(
//         remoteMessagePort,
//         msgId,
//         requestDataRef,
//         k.SendTimeoutInSeconds,
//         k.ReceiveTimeoutInSeconds,
//         c.kCFRunLoopDefaultMode,
//         &responseDataRef,
//     );
//
//     if (helperResponseCode != c.kCFMessagePortSuccess or responseDataRef == null) {
//         Debug.log(
//             .ERROR,
//             "Freetracer failed to communicate with Freetracer Helper Tool - received invalid response code ({d}) or null response data ({any})",
//             .{ helperResponseCode, responseDataRef },
//         );
//         return error.FailedToCommunicateWithHelperTool;
//     }
//
//     // Debug.log(.DEBUG, "@sizeOf(responseDataRef) is: {d}", .{@sizeOf(responseDataRef)});
//     const responseData = try SerializedData.destructCFDataRef(@ptrCast(responseDataRef));
//     const deserializedData = try SerializedData.deserialize(returnType, responseData);
//
//     return deserializedData;
// }

// MacOS-only
// Sends a CFMessage to the Privileged Helper Tool via a CFPort to request helper tool's version
// "Client"-side function, whereas Freetracer acts as the client for the Freetracer Privileged Tool
// @Returns anyeror![k.ResponseDataSize]u8
// pub fn requestHelperVersion() ![k.MachPortPacketSize]u8 {
//     //
//     const response: [k.MachPortPacketSize]u8 = try sendMachMessageToRemote(
//         @TypeOf(null),
//         null,
//         k.HelperVersionRequest,
//         [k.MachPortPacketSize]u8,
//     );
//
//     if (response.len < 1) {
//         Debug.log(.ERROR, "PrivilegedHelperTool.requestHelperVersion(): Freetracer failed to receive a structured response from Freetracer Helper Tool (zero length response).", .{});
//         return error.FailedToRedceiveStructuredResponse;
//     }
//
//     Debug.log(.INFO, "Freetracer successfully received response from Freetracer Helper Tool: {s}", .{std.mem.sliceTo(&response, 0x00)});
//
//     return response;
// }

// MacOS-only
// Sends a CFMessage to the Privileged Helper Tool via a CFPort to request a disk unmount
// "Client"-side function, whereas Freetracer acts as the client for the Freetracer Privileged Tool
// @Returns anyerror!k.HelperUnmountRequestCode
// pub fn requestPerformUnmount(targetDisk: [:0]const u8) !HelperUnmountRequestCode {
//     //
//     const response: HelperReturnCode = try sendMachMessageToRemote(
//         [:0]const u8,
//         targetDisk,
//         k.UnmountDiskRequest,
//         HelperReturnCode,
//     );
//
//     if (response != HelperReturnCode.SUCCESS) {
//         Debug.log(.ERROR, "Freetracer failed to receive a structured response from Freetracer Helper Tool: {d}.", .{@intFromEnum(response)});
//         return HelperUnmountRequestCode.FAILURE;
//     }
//
//     Debug.log(.INFO, "Freetracer successfully received response from Freetracer Helper Tool: {any}", .{response});
//
//     return HelperUnmountRequestCode.SUCCESS;
// }

// Sends a CFMessage to the Privileged Helper Tool via a CFPort to request to flash ISO to disk
// "Client"-side function, whereas Freetracer acts as the client for the Freetracer Privileged Tool
// @Returns anyerror!k.HelperReturnCode
// pub fn requestWriteISO(requestData: [:0]const u8) !HelperReturnCode {
//     // Debug.log(.DEBUG, "requestWiteISO(): requestData: {any}", .{requestData});
//
//     const response: HelperReturnCode = try sendMachMessageToRemote(
//         [:0]const u8,
//         requestData,
//         k.WriteISOToDeviceRequest,
//         HelperReturnCode,
//     );
//
//     if (response != HelperReturnCode.SUCCESS) {
//         Debug.log(.ERROR, "Freetracer failed to receive a structured response from Freetracer Helper Tool: {d}.", .{@intFromEnum(response)});
//         return error.HelperToolRespondedItFailedToWriteISOToDevice;
//     }
//
//     Debug.log(.INFO, "Freetracer received response that Helper Tool successfully flashed ISO to disk.", .{});
//
//     return response;
// }
