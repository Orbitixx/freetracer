// Handles client-side helper installation checks for the privileged SMJobBless helper.
// Exposes APIs used by the unprivileged GUI to verify helper presence and trigger
// installation by negotiating Authorization Services credentials and invoking SMJobBless.
// Performs CoreFoundation resource management and surfaces status as HelperInstallCode enums.
// -------------------------------------------------------------------------------------------
const std = @import("std");
const env = @import("../../env.zig");
const freetracer_lib = @import("freetracer-lib");
const c = freetracer_lib.c;
const k = freetracer_lib.constants.k;
const Debug = freetracer_lib.Debug;
const isMacOS = freetracer_lib.types.isMacOS;

const HelperReturnCode = freetracer_lib.constants.HelperReturnCode;
const HelperInstallCode = freetracer_lib.constants.HelperInstallCode;
const HelperUnmountRequestCode = freetracer_lib.constants.HelperUnmountRequestCode;
const HelperResponseCode = freetracer_lib.constants.HelperResponseCode;

/// MacOS-only.
/// Checks via the SMJobBless system daemon if the privileged helper tool is installed.
/// Caller must run on macOS and the helper bundle id constant must remain valid for the CFString lifetime.
/// Returns HelperInstallCode.{SUCCESS, FAILURE} where FAILURE denotes helper absence or unexpected CF failure.
pub fn isHelperToolInstalled() HelperInstallCode {
    if (!isMacOS) return HelperInstallCode.FAILURE;

    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        env.HELPER_BUNDLE_ID,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );

    if (helperLabel == null) {
        Debug.log(.ERROR, "isHelperToolInstalled(): failed to create CFString for helper bundle id.", .{});
        return HelperInstallCode.FAILURE;
    }

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

/// MacOS-only.
/// Installs the privileged helper tool via macOS SMJobBless after acquiring the bless entitlement.
/// Caller must be the GUI client with appropriate code signature and run off the UI thread due to potential prompts.
/// Returns HelperInstallCode.{SUCCESS, FAILURE} where FAILURE denotes auth negotiation or SMJobBless problems.
pub fn installPrivilegedHelperTool() HelperInstallCode {
    if (!isMacOS) return HelperInstallCode.FAILURE;

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

    if (helperLabel == null) {
        Debug.log(.ERROR, "Install Helper Tool: failed to create helper label CFString.", .{});
        return HelperInstallCode.FAILURE;
    }

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

        const errLen = std.mem.indexOfScalar(u8, errDescBuffer[0..], 0x00) orelse errDescBuffer.len;
        Debug.log(.ERROR, "Freetracer received SMJobBless error: {s}.", .{errDescBuffer[0..@min(errDescBuffer.len, errLen)]});
        return HelperInstallCode.FAILURE;
    }

    if (cfError != null) {
        defer _ = c.CFRelease(cfError);
    }

    if (installStatus == c.TRUE) {
        Debug.log(.INFO, "Freetracer successfully installed its privileged helper tool.", .{});
        return HelperInstallCode.SUCCESS;
    }

    Debug.log(.ERROR, "installPrivilegedHelperTool(): CRITICAL ERROR: Unreachable path reached! o_O", .{});
    unreachable;
}
