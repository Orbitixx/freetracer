/// Reusable text ellipsization utility for fitting text to constrained widths.
/// Provides efficient, DRY ellipsization logic used by multiple UI components.
const std = @import("std");
const rl = @import("raylib");

pub const TextEllipsis = @This();

/// Ellipsizes text to fit within maxWidth pixels, modifying the output buffer in-place.
/// Returns the length of text written to the buffer (including ellipsis).
/// Buffer must be null-terminated.
pub fn ellipsizeToBuffer(
    buffer: []u8,
    value: []const u8,
    font: rl.Font,
    fontSize: f32,
    spacing: f32,
    maxWidth: f32,
) usize {
    const ellipsis: [:0]const u8 = "...";
    const ellipsisLen = ellipsis.len;
    const ellipsisWidth = rl.measureTextEx(font, ellipsis, fontSize, spacing).x;

    // Ensure buffer is large enough
    const maxBufferLen = buffer.len - 1;

    // Clear buffer
    @memset(buffer, 0x00);

    if (value.len == 0) {
        return 0;
    }

    // Try to fit the entire text
    const fullLen = @min(value.len, maxBufferLen);
    @memcpy(buffer[0..fullLen], value[0..fullLen]);
    buffer[fullLen] = 0;

    if (measureText(buffer[0..fullLen :0], font, fontSize, spacing) <= maxWidth) {
        return fullLen;
    }

    // Text doesn't fit; check if ellipsis alone fits
    if (ellipsisWidth > maxWidth) {
        @memset(buffer, 0x00);
        return 0;
    }

    // Binary search or linear search for the longest prefix that fits with ellipsis
    var prefixLen: usize = if (maxBufferLen > ellipsisLen)
        @min(value.len, maxBufferLen - ellipsisLen)
    else
        0;

    while (true) {
        const totalLen = prefixLen + ellipsisLen;

        if (totalLen <= maxBufferLen) {
            // Write prefix + ellipsis
            if (prefixLen > 0) {
                @memcpy(buffer[0..prefixLen], value[0..prefixLen]);
            }
            @memcpy(buffer[prefixLen .. prefixLen + ellipsisLen], ellipsis[0..ellipsisLen]);
            buffer[totalLen] = 0;

            if (measureText(buffer[0..totalLen :0], font, fontSize, spacing) <= maxWidth) {
                return totalLen;
            }
        }

        if (prefixLen == 0) break;
        prefixLen -= 1;
    }

    // Fallback: just show ellipsis
    if (ellipsisLen <= maxBufferLen) {
        @memcpy(buffer[0..ellipsisLen], ellipsis[0..ellipsisLen]);
        buffer[ellipsisLen] = 0;
        return ellipsisLen;
    }

    // Last resort: empty
    @memset(buffer, 0x00);
    return 0;
}

/// Measures the pixel width of a null-terminated text string.
fn measureText(text: [:0]const u8, font: rl.Font, fontSize: f32, spacing: f32) f32 {
    const dims = rl.measureTextEx(font, text, fontSize, spacing);
    return dims.x;
}
