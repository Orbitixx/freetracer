//! Privileged Helper Tool Installation Module
//!
//! Manages installation and verification of the privileged launchd daemon used by
//! Freetracer for disk operations requiring elevated privileges.
//!
//! **Responsibilities:**
//! - Query launchd daemon to verify if helper is installed and registered
//! - Acquire Authorization Services credentials from user via Security Agent
//! - Install helper via SMJobBless with appropriate code signature entitlements
//! - Extract and log detailed error information from CoreFoundation errors
//!
//! **Security Model:**
//! - All operations run in unprivileged GUI process context
//! - User must approve installation via Authorization Services dialog
//! - Helper bundle must be code-signed and included in app bundle
//! - Installation persists in launchd system domain (~/.launchAgents or /Library/LaunchDaemons)
//!
//! **Error Handling:**
//! - All public functions return typed error unions (HelperToolError)
//! - Detailed error extraction from CFError when available
//! - Structured logging at appropriate severity levels for debugging
//! - Proper CoreFoundation resource cleanup via defer statements

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

/// Comprehensive error type for privileged helper tool operations.
/// Distinguishes between different failure modes for proper error handling and recovery.
pub const HelperToolError = error{
    /// Not running on macOS (required for SMJobBless APIs)
    NotMacOS,

    /// Failed to create CFString for helper bundle ID
    CFStringCreationFailed,

    /// SMJobCopyDictionary returned NULL (helper not installed)
    SMJobCopyDictionaryFailed,

    /// Failed to create Authorization Services reference
    AuthorizationCreationFailed,

    /// Failed to copy authorization rights (user denied or other issue)
    AuthorizationRightsCopyFailed,

    /// SMJobBless call failed to install helper
    SMJobBlessFailed,

    /// Failed to extract error description from CFError
    ErrorDescriptionCopyFailed,

    /// Failed to convert CFString error to C string
    ErrorStringConversionFailed,
};

/// Buffer size for extracted error descriptions from CFError.
/// CFError descriptions typically fit in 256 bytes; 512 provides safety margin.
const ERROR_DESCRIPTION_BUFFER_SIZE = 512;

/// Authorization flags required for SMJobBless installation.
/// Combines the following behaviors:
/// - kAuthorizationFlagDefaults: Use standard authorization semantics
/// - kAuthorizationFlagInteractionAllowed: Permit Security Agent user interaction
/// - kAuthorizationFlagPreAuthorize: Request authorization before copying rights
/// - kAuthorizationFlagExtendRights: Extend rights if user grants permission
const SMJOB_BLESS_AUTH_FLAGS: c.AuthorizationFlags =
    c.kAuthorizationFlagDefaults |
    c.kAuthorizationFlagInteractionAllowed |
    c.kAuthorizationFlagPreAuthorize |
    c.kAuthorizationFlagExtendRights;

/// Creates a CFString reference for the helper bundle ID.
///
/// Allocates a CFString with no-copy semantics pointing to the
/// helper bundle ID constant. Caller must CFRelease when done.
///
/// Returns: CFStringRef to helper bundle ID string
/// Errors: CFStringCreationFailed if CFString creation fails
fn createHelperBundleIDString() HelperToolError!c.CFStringRef {
    const helperLabel: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        env.HELPER_BUNDLE_ID,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );

    if (helperLabel == null) {
        Debug.log(.ERROR, "Failed to create CFString for helper bundle ID", .{});
        return HelperToolError.CFStringCreationFailed;
    }

    return helperLabel;
}

/// Checks if the privileged helper tool is installed and registered with launchd.
///
/// Queries the system launchd daemon to determine whether the helper has been
/// previously installed and registered. This check is essential for determining
/// whether installation is needed before prompting user for authorization.
///
/// **Thread Safety:** Safe to call from any thread; uses only local variables.
///
/// **Arguments:**
///   None - uses env.HELPER_BUNDLE_ID constant
///
/// **Returns:**
///   HelperInstallCode.SUCCESS if helper is installed and registered
///   HelperInstallCode.FAILURE if helper not found (installation needed)
///
/// **Errors:**
///   - NotMacOS: Not running on macOS (SMJobBless APIs unavailable)
///   - CFStringCreationFailed: Failed to create CFString for bundle ID
///   - SMJobCopyDictionaryFailed: SMJobCopyDictionary returned NULL (helper missing)
pub fn isHelperToolInstalled() HelperToolError!HelperInstallCode {
    if (!isMacOS) return HelperToolError.NotMacOS;

    const helperLabel = try createHelperBundleIDString();
    defer _ = c.CFRelease(helperLabel);

    const smJobCopyDict = c.SMJobCopyDictionary(c.kSMDomainSystemLaunchd, helperLabel);

    if (smJobCopyDict == null) {
        Debug.log(.WARNING, "Helper tool not found in launchd (installation needed)", .{});
        return HelperInstallCode.FAILURE;
    }

    defer _ = c.CFRelease(smJobCopyDict);

    Debug.log(.INFO, "Helper tool is installed and registered with launchd", .{});
    return HelperInstallCode.SUCCESS;
}

/// Creates an empty Authorization Services reference.
///
/// Establishes initial authorization context with no pre-authorized rights.
/// Rights must be extended via AuthorizationCopyRights before use.
///
/// Returns: AuthorizationRef for use with other Authorization APIs
/// Errors: AuthorizationCreationFailed if creation fails
fn createAuthorizationRef() HelperToolError!c.AuthorizationRef {
    var authRef: c.AuthorizationRef = undefined;

    const authStatus = c.AuthorizationCreate(
        k.NullAuthorizationRights,
        k.NullAuthorizationEnvironment,
        k.EmptyAuthotizationFlags,
        &authRef,
    );

    if (authStatus != c.errAuthorizationSuccess) {
        Debug.log(.ERROR, "AuthorizationCreate failed: status={d}", .{authStatus});
        return HelperToolError.AuthorizationCreationFailed;
    }

    return authRef;
}

/// Extends authorization to include SMJobBless privilege.
///
/// Requests the specific right needed to invoke SMJobBless and install
/// the privileged helper. This may trigger Security Agent UI prompting
/// user for password or biometric authentication.
///
/// **Arguments:**
///   authRef: Authorization reference to extend
///
/// **Errors:**
///   - AuthorizationRightsCopyFailed: User denied, password failed, or other error
fn extendAuthorizationRights(authRef: c.AuthorizationRef) HelperToolError!void {
    var authItem = c.AuthorizationItem{
        .name = c.kSMRightBlessPrivilegedHelper,
        .flags = k.EmptyAuthorizationItemFlags,
        .value = k.NullAuthorizationItemValue,
        .valueLength = k.ZeroAuthorizationItemValueLength,
    };

    const authRights: c.AuthorizationRights = .{ .count = 1, .items = &authItem };

    const authStatus = c.AuthorizationCopyRights(
        authRef,
        &authRights,
        k.NullAuthorizationEnvironment,
        SMJOB_BLESS_AUTH_FLAGS,
        k.NullAuthorizationRights,
    );

    if (authStatus != c.errAuthorizationSuccess) {
        Debug.log(.ERROR, "AuthorizationCopyRights failed: status={d}", .{authStatus});
        return HelperToolError.AuthorizationRightsCopyFailed;
    }
}

/// Installs the privileged helper tool via macOS SMJobBless.
///
/// Acquires necessary authorization rights from user via Security Agent dialog,
/// then invokes SMJobBless to install and register the helper with launchd.
/// This operation requires user approval and may take several seconds.
///
/// **Caller Requirements:**
///   - Must run on macOS (will return NotMacOS error otherwise)
///   - Must run off UI thread (user interaction via Security Agent)
///   - Helper app bundle must exist in Resources with correct code signature
///   - App must have SMJobBless entitlement in code signature
///
/// **Thread Safety:** NOT thread-safe; only call once during app initialization.
///
/// **Returns:** Void on success (helper now registered with launchd)
///
/// **Errors:**
///   - NotMacOS: Not running on macOS
///   - CFStringCreationFailed: Failed to create CFString for bundle ID
///   - AuthorizationCreationFailed: Could not create authorization reference
///   - AuthorizationRightsCopyFailed: User denied, password failed, or other auth issue
///   - SMJobBlessFailed: SMJobBless call failed (may include CFError details in logs)
///   - ErrorDescriptionCopyFailed: Could not extract error details from CFError
///   - ErrorStringConversionFailed: Could not convert CFString error to C string
pub fn installHelperTool() HelperToolError!void {
    if (!isMacOS) return HelperToolError.NotMacOS;

    // Step 1: Create empty authorization reference
    const authRef = try createAuthorizationRef();
    defer _ = c.AuthorizationFree(authRef, c.kAuthorizationFlagDefaults);

    // Step 2: Extend authorization to include SMJobBless right (may prompt user)
    try extendAuthorizationRights(authRef);

    // Step 3: Create CFString reference for helper bundle ID
    const helperLabel = try createHelperBundleIDString();
    defer _ = c.CFRelease(helperLabel);

    // Step 4: Invoke SMJobBless to install helper
    var cfError: c.CFErrorRef = null;
    const installStatus = c.SMJobBless(
        c.kSMDomainSystemLaunchd,
        helperLabel,
        authRef,
        &cfError,
    );

    // Step 5: Handle results
    if (installStatus != c.TRUE) {
        Debug.log(.ERROR, "SMJobBless failed to install helper", .{});

        // Attempt to extract detailed error information for debugging
        if (cfError != null) {
            defer _ = c.CFRelease(cfError);

            const errorDesc = c.CFErrorCopyDescription(cfError);
            if (errorDesc != null) {
                defer _ = c.CFRelease(errorDesc);

                var errDescBuffer: [ERROR_DESCRIPTION_BUFFER_SIZE]u8 = undefined;
                if (c.CFStringGetCString(
                    errorDesc,
                    &errDescBuffer,
                    errDescBuffer.len,
                    c.kCFStringEncodingUTF8,
                ) != 0) {
                    const errLen = std.mem.indexOfScalar(u8, errDescBuffer[0..], 0x00) orelse errDescBuffer.len;
                    Debug.log(.ERROR, "SMJobBless error: {s}", .{
                        errDescBuffer[0..@min(errDescBuffer.len, errLen)],
                    });
                }
            }
        }

        return HelperToolError.SMJobBlessFailed;
    }

    Debug.log(.INFO, "Helper tool installed successfully", .{});
}

/// Legacy alias for installHelperTool(). Maintains backward compatibility.
/// Prefer installHelperTool() for new code.
pub fn installPrivilegedHelperTool() HelperInstallCode {
    installHelperTool() catch |err| {
        Debug.log(.ERROR, "Helper installation failed: {any}", .{err});
        return HelperInstallCode.FAILURE;
    };
    return HelperInstallCode.SUCCESS;
}
