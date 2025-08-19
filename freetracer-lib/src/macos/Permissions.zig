const c = @import("../types.zig").c;
const Debug = @import("../util/debug.zig");

pub fn openPrivacySettings() void {
    const urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy";

    const urlCFString: c.CFStringRef = @ptrCast(c.CFStringCreateWithCString(
        c.kCFAllocatorDefault,
        urlString,
        c.kCFStringEncodingUTF8,
    ));

    if (urlCFString == null) {
        // TODO: Handle error
        Debug.log(.ERROR, "Unable to create a Core Foundation CFString.", .{});
        return;
    }

    defer c.CFRelease(urlCFString);

    const url: c.CFURLRef = c.CFURLCreateWithString(c.kCFAllocatorDefault, urlCFString, null);

    if (url == null) {
        // TODO: Handle error
        Debug.log(.ERROR, "Unable to create a Core Foundation URL from CFString.", .{});
        return;
    }

    defer c.CFRelease(url);

    const result = c.LSOpenCFURLRef(url, null);

    Debug.log(.INFO, "Open settings result is: {any}", .{result});
}
