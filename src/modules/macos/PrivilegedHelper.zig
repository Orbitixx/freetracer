const std = @import("std");
const c = @import("../../lib/sys/system.zig").c;
const env = @import("../../env.zig");
const k = @import("../../lib/constants.zig");
const debug = @import("../../lib/util/debug.zig");

pub fn isHelperToolInstalled() bool {
    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, env.HELPER_BUNDLE_ID, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(helperLabel);

    const smJobCopyDict = c.SMJobCopyDictionary(c.kSMDomainSystemLaunchd, helperLabel);

    if (smJobCopyDict == null) {
        debug.printf("isHelperToolInstalled(): the SMJobCopyDictionary for helper tool is NULL. Helper tool is NOT installed.", .{});
        return false;
    }

    defer _ = c.CFRelease(smJobCopyDict);

    debug.printf("isHelperToolInstalled(): Helper tool found, it appears to be installed.", .{});
    return true;
}

pub fn installPrivilegedHelperTool() bool {
    var installStatus: c.Boolean = c.FALSE;

    debug.print("Install Helper Tool: attempting to obtain initial (empty) authorization.");

    var authRef: c.AuthorizationRef = undefined;
    var authStatus: c.OSStatus = c.AuthorizationCreate(null, null, 0, &authRef);

    if (authStatus != c.errAuthorizationSuccess) {
        debug.printf("Freetracer failed to obtain empty authorization in the process of installing its privileged helper tool. AuthStatus: {d}.", .{authStatus});
        authRef = null;
        return false;
    }

    debug.print("Install Helper Tool: successfully obtained an empty authorization.");

    defer _ = c.AuthorizationFree(authRef, c.kAuthorizationFlagDefaults);

    var authItem = c.AuthorizationItem{ .name = c.kSMRightBlessPrivilegedHelper, .flags = 0, .value = null, .valueLength = 0 };

    const authRights: c.AuthorizationRights = .{ .count = 1, .items = &authItem };
    const authFlags: c.AuthorizationFlags = c.kAuthorizationFlagDefaults | c.kAuthorizationFlagInteractionAllowed | c.kAuthorizationFlagPreAuthorize | c.kAuthorizationFlagExtendRights;

    debug.print("Install Helper Tool: attempting to copy authorization rights to authorization ref.");

    authStatus = c.AuthorizationCopyRights(authRef, &authRights, null, authFlags, null);

    if (authStatus != c.errAuthorizationSuccess) {
        debug.printf("Freetracer failed to obtain specific authorization rights in the process of installing its privileged helper tool. AuthStatus: {d}.", .{authStatus});
        return false;
    }

    debug.print("Install Helper Tool: successfully copied auth rights; attempting to create a bundle id CFStringRef.");

    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, env.HELPER_BUNDLE_ID, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(helperLabel);

    debug.print("Install Helper Tool: successfully created a bundle id CFStringRef.");

    var cfError: c.CFErrorRef = null;

    debug.print("Install Helper Tool: launching SMJobBless call on the helper.");

    installStatus = c.SMJobBless(c.kSMDomainSystemLaunchd, helperLabel, authRef, &cfError);

    debug.print("Install Helper Tool: SMJobBless call completed without kernel panicking.");

    if (installStatus == c.TRUE) {
        debug.printf("Freetracer successfully installed its privileged helper tool.", .{});
        return true;
    }

    debug.print("Install Helper Tool: SMJobBless call failed, proceeding to analyze error.");

    if (cfError == null) {
        debug.printf("Freetracer failed to install its privileged helper tool without any error status from SMJobBless.", .{});
        return false;
    }

    defer _ = c.CFRelease(cfError);

    debug.print("Install Helper Tool: attempting to copy error description.");

    const errorDesc = c.CFErrorCopyDescription(cfError);

    if (errorDesc == null) {
        debug.printf("Freetracer could not copy error description from the SMJobBless operation error, error description is null.", .{});
        return false;
    }

    debug.print("Install Helper Tool: obtained a copy of error description.");

    defer _ = c.CFRelease(errorDesc);

    debug.print("Install Helper Tool: attempting to obtain a string from error description.");

    var errDescBuffer: [512]u8 = undefined;
    const obtainErrorDescStatus = c.CFStringGetCString(errorDesc, &errDescBuffer, errDescBuffer.len, c.kCFStringEncodingUTF8);

    if (obtainErrorDescStatus == 0) {
        debug.printf("Freetracer could not obtain error description from the SMJobBless operation error, error description is NOT null.", .{});
        return false;
    }

    debug.printf("Freetracer received SMJobBless error: {s}.", .{std.mem.sliceTo(&errDescBuffer, 0)});
    return false;
}

pub fn performPrivilegedTask() bool {
    const portNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        env.HELPER_BUNDLE_ID,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );
    defer _ = c.CFRelease(portNameRef);

    const remoteMessagePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, portNameRef);

    if (remoteMessagePort == null) {
        debug.printf("Freetracer unable to create a remote message port to Freetracer Helper Tool.", .{});
        return false;
    }

    defer _ = c.CFRelease(remoteMessagePort);

    const dataPayload: i32 = 200;
    const dataPayloadBytePtr: [*c]const u8 = @ptrCast(&dataPayload);

    const requestDataRef: c.CFDataRef = c.CFDataCreate(c.kCFAllocatorDefault, dataPayloadBytePtr, @sizeOf(i32));
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

    if (helperResponseCode != c.kCFMessagePortSuccess or responseData == null) {
        debug.printf(
            "Freetracer failed to communicate with Freetracer Helper Tool - received invalid response code ({d}) or null response data ({any}).",
            .{ helperResponseCode, responseData },
        );
        return false;
    }

    var result: i32 = -1;

    if (c.CFDataGetLength(responseData) >= @sizeOf(i32)) {
        const dataPtr = c.CFDataGetBytePtr(responseData);
        const resultPtr: *const i32 = @ptrCast(@alignCast(dataPtr));
        result = resultPtr.*;
    }

    if (result == 0) {
        debug.printf("Freetracer successfully received reseponse from Freetracer Helper Tool: {d}", .{result});
        return true;
    } else {
        debug.printf("Freetracer recieved unsuccessful response from Freetracer Helper Tool: {d}.", .{result});
        return false;
    }
}
