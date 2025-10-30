//! Currently deprecated and unused. Though may be useful in helping
//! users troubleshoot error messages and opening the currect Settings
//! screen. Leaving in for now.

const c = @import("../types.zig").c;
const Debug = @import("../util/debug.zig");

pub const OpenSettingsError = error{
    CreateCFStringFailed,
    CreateURLFailed,
    LaunchFailed,
};

/// Opens the macOS Privacy settings pane and logs failures. The infallible API
/// is preserved for existing callers; use `openPrivacySettingsChecked` when
/// error handling is required.
pub fn openPrivacySettings() void {
    _ = openPrivacySettingsChecked() catch |err| {
        Debug.log(.ERROR, "Unable to open Privacy settings: {any}", .{err});
    };
}

/// Opens the macOS Privacy settings pane. Returns an error when any Core
/// Foundation object fails to materialize or the launch services call fails.
pub fn openPrivacySettingsChecked() OpenSettingsError!void {
    const urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy";

    const urlCFString: c.CFStringRef = @ptrCast(c.CFStringCreateWithCString(
        c.kCFAllocatorDefault,
        urlString,
        c.kCFStringEncodingUTF8,
    ));

    if (urlCFString == null) return OpenSettingsError.CreateCFStringFailed;

    defer c.CFRelease(urlCFString);

    const url: c.CFURLRef = c.CFURLCreateWithString(c.kCFAllocatorDefault, urlCFString, null);

    if (url == null) return OpenSettingsError.CreateURLFailed;

    defer c.CFRelease(url);

    const result = c.LSOpenCFURLRef(url, null);

    if (result != c.errSecSuccess and result != 0) {
        return OpenSettingsError.LaunchFailed;
    }

    Debug.log(.INFO, "Successfully requested the Privacy settings pane (status: {d})", .{result});
}
