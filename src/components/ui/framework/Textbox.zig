// Wrappable textbox example from raylib.com
// https://www.raylib.com/examples/text/loader.html?name=text_rectangle_bounds

const std = @import("std");
const rl = @import("raylib");

const Debug = @import("freetracer-lib").Debug;

const UIFramework = @import("./import.zig");
const UIEvent = UIFramework.UIEvent;
const Transform = UIFramework.Transform;
const Rectangle = UIFramework.Rectangle;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElementCallbacks = UIFramework.UIElementCallbacks;

const Styles = @import("../Styles.zig");
const RectangleStyle = Styles.RectangleStyle;
const TextStyle = UIFramework.Text.TextStyle;
const Color = Styles.Color;

const ResourceManagerImport = @import("../../../managers/ResourceManager.zig");
const ResourceManager = ResourceManagerImport.ResourceManagerSingleton;

pub const TextboxStyle = struct {
    background: RectangleStyle = .{},
    text: TextStyle = .{},
    selectionTextTint: rl.Color = Color.white,
    selectionBackgroundTint: rl.Color = Color.themePrimary,
    lineSpacing: f32 = 0,
};

pub const Params = struct {
    identifier: ?UIElementIdentifier = null,
    background: ?Rectangle = null,
    callbacks: UIElementCallbacks = .{},
    wordWrap: bool = true,
    useExtendedTextBuffer: bool = false,
};

pub const Selection = struct {
    start: i32,
    length: i32,
};

const MAX_TEXT_LENGTH = 256;

const Textbox = @This();

allocator: std.mem.Allocator,
identifier: ?UIElementIdentifier = null,
transform: Transform,
style: TextboxStyle,
font: rl.Font,
params: Params = .{},
selection: ?Selection = null,
background: ?Rectangle = null,
textBuffer: [MAX_TEXT_LENGTH]u8 = undefined,
text: [:0]const u8,
callbacks: UIElementCallbacks = .{},
active: bool = true,
isUsingExtendedBuffer: bool = false,
extendedTextBuffer: [8192]u8 = undefined,
autoSize: bool = false,
contentWidth: f32 = 0,
contentHeight: f32 = 0,

pub fn init(allocator: std.mem.Allocator, text: [:0]const u8, transform: Transform, style: TextboxStyle, params: Params) Textbox {
    return .{
        .identifier = params.identifier,
        .allocator = allocator,
        .transform = transform,
        .background = params.background,
        .style = style,
        .text = text,
        .textBuffer = std.mem.zeroes([MAX_TEXT_LENGTH]u8),
        .font = ResourceManager.getFont(style.text.font),
        .params = params,
        .isUsingExtendedBuffer = params.useExtendedTextBuffer,
        .autoSize = false,
        .contentWidth = 0,
        .contentHeight = 0,
    };
}

pub fn start(self: *Textbox) !void {
    // First resolve transform to get max width/height constraints
    self.transform.resolve();
    if (self.background) |*bg| bg.transform.resolve();

    if (self.isUsingExtendedBuffer) {
        self.extendedTextBuffer = std.mem.zeroes([8192]u8);
        if (self.text.len > 0) self.appendText(self.text);
    }

    self.setText(self.text);

    // Now calculate content dimensions after we have the text and constraints
    if (self.autoSize) {
        self.updateContentDimensions();
        // Re-resolve with content dimensions if they're valid
        if (self.contentHeight > 0) {
            self.transform.resolve();
        }
    }
}

pub fn update(self: *Textbox) !void {
    if (!self.active) return;

    self.transform.resolve();
    if (self.background) |*bg| bg.transform.resolve();

    // Update content dimensions after resolving transform so resolved_max_width is available
    if (self.autoSize) {
        self.updateContentDimensions();
        // Re-resolve to apply content dimensions
        self.transform.resolve();
        if (self.background) |*bg| bg.transform.resolve();
    }
}

pub fn draw(self: *Textbox) !void {
    if (!self.active) return;

    if (self.background) |*bg| try bg.draw();

    const textToDraw = if (self.isUsingExtendedBuffer) blk: {
        const extendedSlice = self.extendedBufferDisplaySlice();
        break :blk if (extendedSlice.len == 0) self.text else extendedSlice;
    } else self.text;

    // Use the actual resolved rectangle for drawing, which now includes content-based sizing
    const drawRect = self.transform.asRaylibRectangle();

    drawTextBoxed(
        self.font,
        textToDraw,
        drawRect,
        self.style.text.fontSize,
        self.style.text.spacing,
        self.params.wordWrap,
        self.style.text.textColor,
        self.style.lineSpacing,
    );
}

pub fn setText(self: *Textbox, text: [:0]const u8) void {
    if (text.len > MAX_TEXT_LENGTH) Debug.log(
        .WARNING,
        "Textbox UIElement's value length exceeded allowed max: {s}",
        .{text},
    );

    var textValue: [MAX_TEXT_LENGTH]u8 = std.mem.zeroes([MAX_TEXT_LENGTH]u8);
    @memcpy(
        textValue[0..if (text.len > MAX_TEXT_LENGTH) MAX_TEXT_LENGTH else text.len],
        if (text.len > MAX_TEXT_LENGTH) text[0..MAX_TEXT_LENGTH] else text,
    );

    self.textBuffer = textValue;
    self.text = @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00));

    // Update content dimensions when text changes
    if (self.autoSize) {
        self.updateContentDimensions();
    }
}

pub fn appendText(self: *Textbox, text: [:0]const u8) void {
    if (!self.isUsingExtendedBuffer) return;

    const currentLen: usize = (std.mem.sliceTo(&self.extendedTextBuffer, 0x00)).len;

    if (currentLen + text.len > 8192) {
        return Debug.log(.WARNING, "Textbox's extended text buffer is full, dropping additional append requests!", .{});
    }

    @memcpy(self.extendedTextBuffer[currentLen .. currentLen + text.len], text);

    // Update content dimensions when text changes
    if (self.autoSize) {
        self.updateContentDimensions();
    }
}

pub fn setSelection(self: *Textbox, selection: ?Selection) void {
    self.selection = selection;
}

pub fn setWordWrap(self: *Textbox, flag: bool) void {
    self.params.wordWrap = flag;
}

pub fn onEvent(self: *Textbox, event: UIEvent) void {
    switch (event) {
        inline else => |e| if (e.target != self.identifier) return,
    }

    // Debug.log(.DEBUG, "Textbox ({any}) recevied a UIEvent: {any}", .{ self.identifier, event });

    switch (event) {
        .TextChanged => |e| {
            if (e.text) |newText| {
                if (self.isUsingExtendedBuffer) self.appendText(newText) else self.setText(newText);
            }

            if (e.style) |textStyle| {
                self.style.text = textStyle;
                // Recalculate dimensions if font size changed
                if (self.autoSize) {
                    self.updateContentDimensions();
                }
            }
        },
        .CopyTextToClipboard => {
            if (self.isUsingExtendedBuffer)
                rl.setClipboardText(@ptrCast(std.mem.sliceTo(&self.extendedTextBuffer, 0x00)))
            else
                rl.setClipboardText(self.text);
        },
        inline else => {},
    }
}

pub fn updateContentDimensions(self: *Textbox) void {
    if (!self.autoSize) return;

    const textToDraw = if (self.isUsingExtendedBuffer) blk: {
        const extendedSlice = self.extendedBufferDisplaySlice();
        break :blk if (extendedSlice.len == 0) self.text else extendedSlice;
    } else self.text;

    // Calculate the actual dimensions of the text content
    const dims = self.calculateTextDimensions(
        textToDraw,
        self.style.text.fontSize,
        self.style.text.spacing,
        self.params.wordWrap,
        self.style.lineSpacing,
    );

    self.contentWidth = dims.width;
    self.contentHeight = dims.height;

    // Only update height for content-based sizing (not width to avoid cutoff)
    // Only enable content sizing if we have valid dimensions
    if (dims.height > 0) {
        self.transform.content_width = null; // Don't use content width
        self.transform.content_height = dims.height;
        self.transform.use_content_size = true;
    } else {
        // Don't use content sizing if we don't have valid dimensions
        self.transform.use_content_size = false;
    }
}

fn calculateTextDimensions(
    self: *Textbox,
    text: [:0]const u8,
    fontSize: f32,
    spacing: f32,
    wordWrap: bool,
    extraLineSpacing: f32,
) struct { width: f32, height: f32 } {
    if (text.len == 0) return .{ .width = 0, .height = fontSize };

    const font = self.font;
    const scaleFactor: f32 = if (font.baseSize == 0) 1 else fontSize / @as(f32, @floatFromInt(font.baseSize));
    const baseLineHeight: f32 = @as(f32, @floatFromInt(if (font.baseSize == 0) @as(i32, @intFromFloat(fontSize)) else font.baseSize)) * scaleFactor;

    // Use resolved max width if available for proper word wrapping
    const wrapWidth: f32 = if (self.transform.resolved_max_width) |mw|
        mw
    else
        // If no max width is set, use a very large value (no wrapping)
        999999;

    // Simple approach: calculate line by line
    var maxLineWidth: f32 = 0;
    var currentLineWidth: f32 = 0;
    var lineCount: u32 = 1;

    var textIndex: usize = 0;
    var lastWordBreak: usize = 0;
    var lastWordBreakWidth: f32 = 0;

    while (textIndex < text.len) {
        var codepointByteCount: i32 = 0;
        const remaining: [:0]const u8 = text[textIndex..];
        const codepoint = rl.getCodepoint(remaining, &codepointByteCount);
        var glyphIndex = rl.getGlyphIndex(font, codepoint);

        if (codepoint == 0x3f) codepointByteCount = 1;

        if (glyphIndex < 0) glyphIndex = 0;
        const glyphIndexUsize = @as(usize, @intCast(glyphIndex));

        var glyphWidth: f32 = 0;
        if (codepoint != '\n') {
            const advance = font.glyphs[glyphIndexUsize].advanceX;
            glyphWidth = if (advance == 0)
                font.recs[glyphIndexUsize].width * scaleFactor
            else
                @as(f32, @floatFromInt(advance)) * scaleFactor;

            // Add spacing between characters (but not after the last one)
            if (textIndex + @as(usize, @intCast(codepointByteCount)) < text.len) {
                glyphWidth += spacing;
            }
        }

        // Track word breaks for wrapping
        if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n') {
            lastWordBreak = textIndex;
            lastWordBreakWidth = currentLineWidth;
        }

        // Handle different line break scenarios
        if (codepoint == '\n') {
            // Explicit line break
            maxLineWidth = @max(maxLineWidth, currentLineWidth);
            currentLineWidth = 0;
            lineCount += 1;
            lastWordBreak = textIndex + @as(usize, @intCast(codepointByteCount));
            lastWordBreakWidth = 0;
        } else if (wordWrap and (currentLineWidth + glyphWidth) > wrapWidth) {
            // Need to wrap
            if (lastWordBreak > 0 and lastWordBreak != textIndex) {
                // Wrap at last word boundary
                maxLineWidth = @max(maxLineWidth, lastWordBreakWidth);
                currentLineWidth = currentLineWidth - lastWordBreakWidth;
            } else {
                // No word boundary, wrap at current position
                maxLineWidth = @max(maxLineWidth, currentLineWidth);
                currentLineWidth = glyphWidth;
            }
            lineCount += 1;
        } else {
            // Normal character, add to current line
            currentLineWidth += glyphWidth;
        }

        textIndex += @as(usize, @intCast(codepointByteCount));
    }

    // Don't forget the last line
    maxLineWidth = @max(maxLineWidth, currentLineWidth);

    // IMPORTANT: Calculate height correctly for text rendering
    // The drawTextBoxedSelectable function uses baseLineHeight for its rendering checks:
    // if ((textOffsetY + baseLineHeight) > rect.height) break;
    //
    // It increments textOffsetY by lineStep between lines, but checks against baseLineHeight for rendering.
    // For N lines, the minimum height needed is:
    // - Line 0 at Y=0: needs 0 + baseLineHeight = baseLineHeight
    // - Line 1 at Y=lineStep: needs lineStep + baseLineHeight
    // - Line N at Y=N*lineStep: needs N*lineStep + baseLineHeight
    //
    // So minimum rect.height = (lineCount - 1) * lineStep + baseLineHeight
    // But we should also account for the visual spacing, so we use:
    // rect.height = lineCount * baseLineHeight + (lineCount - 1) * extraLineSpacing
    // which simplifies to: lineCount * lineStep + max(0, -extraLineSpacing) to ensure space for the first line

    const resultWidth = maxLineWidth;
    const minHeightForLines = @as(f32, @floatFromInt(lineCount)) * baseLineHeight + @max(0, -extraLineSpacing) * (@as(f32, @floatFromInt(lineCount)) - 1);

    return .{ .width = resultWidth, .height = minHeightForLines };
}

pub fn deinit(self: *Textbox) void {
    _ = self;
}

fn extendedBufferDisplaySlice(self: *Textbox) [:0]const u8 {
    const buffer: [:0]const u8 = @ptrCast(std.mem.sliceTo(&self.extendedTextBuffer, 0x00));
    if (buffer.len == 0) return buffer;

    const rect = self.transform.asRaylibRectangle();
    if (rect.width <= 0 or rect.height <= 0) return buffer[buffer.len..];

    const plain: []const u8 = buffer[0..buffer.len];

    var current_start = findLineStart(plain, plain.len);
    if (current_start == plain.len and plain.len > 0) {
        if (findPrevLineStart(plain, current_start)) |prev| {
            current_start = prev;
        } else {
            return buffer[buffer.len..];
        }
    }

    var best_start = current_start;
    var has_fit = false;

    while (true) {
        if (!self.sliceFitsFrom(buffer, current_start, rect)) {
            if (!has_fit) best_start = current_start;
            break;
        }

        has_fit = true;
        best_start = current_start;

        if (current_start == 0) break;

        const prev = findPrevLineStart(plain, current_start) orelse break;
        if (prev == current_start) break;
        current_start = prev;
    }

    return buffer[best_start..];
}

fn sliceFitsFrom(self: *Textbox, buffer: [:0]const u8, start_index: usize, rect: rl.Rectangle) bool {
    const candidate = buffer[start_index..];
    return textFitsInRect(
        self.font,
        candidate,
        rect,
        self.style.text.fontSize,
        self.style.text.spacing,
        self.params.wordWrap,
        self.style.lineSpacing,
    );
}

fn textFitsInRect(
    font: rl.Font,
    text: [:0]const u8,
    rect: rl.Rectangle,
    fontSize: f32,
    spacing: f32,
    wordWrap: bool,
    extraLineSpacing: f32,
) bool {
    if (text.len == 0) return true;
    if (rect.width <= 0 or rect.height <= 0) return false;

    const scaleFactor: f32 = if (font.baseSize == 0) 1 else fontSize / @as(f32, @floatFromInt(font.baseSize));
    const baseLineHeight: f32 = if (font.baseSize == 0) fontSize else @as(f32, @floatFromInt(font.baseSize)) * scaleFactor;

    var lineStep = baseLineHeight + extraLineSpacing;
    if (lineStep <= 0) lineStep = baseLineHeight;
    if (lineStep <= 0) return false;

    var textOffsetY: f32 = 0;
    var textOffsetX: f32 = 0;

    const measureState: i32 = 0;
    const drawState: i32 = 1;

    var state: i32 = if (wordWrap) measureState else drawState;
    var startLine: i32 = -1;
    var endLine: i32 = -1;
    var lastGlyphIndex: i32 = -1;

    var textIndex: usize = 0;
    var glyphCounter: i32 = 0;

    while (textIndex < text.len) {
        const glyphStartIndex = textIndex;
        var codepointByteCount: i32 = 0;
        const remaining: [:0]const u8 = text[textIndex..];
        const codepoint = rl.getCodepoint(remaining, &codepointByteCount);
        var glyphIndex = rl.getGlyphIndex(font, codepoint);

        if (codepoint == 0x3f) codepointByteCount = 1;
        textIndex += @as(usize, @intCast(codepointByteCount));
        const currentEndIndex = @as(i32, @intCast(textIndex));

        if (glyphIndex < 0) glyphIndex = 0;
        const glyphIndexUsize = @as(usize, @intCast(glyphIndex));

        var glyphWidth: f32 = 0;
        if (codepoint != '\n') {
            const advance = font.glyphs[glyphIndexUsize].advanceX;
            glyphWidth = if (advance == 0)
                font.recs[glyphIndexUsize].width * scaleFactor
            else
                @as(f32, @floatFromInt(advance)) * scaleFactor;

            if (textIndex < text.len) glyphWidth += spacing;
        }

        if (state == measureState) {
            if (startLine < 0) startLine = @as(i32, @intCast(glyphStartIndex));
            if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n') endLine = currentEndIndex;

            if ((textOffsetX + glyphWidth) > rect.width) {
                endLine = if (endLine < 1) currentEndIndex else endLine;
                if (currentEndIndex == endLine) endLine -= codepointByteCount;
                if ((startLine + codepointByteCount) == endLine) endLine = currentEndIndex - codepointByteCount;

                state = drawState;
            } else if (textIndex >= text.len) {
                endLine = currentEndIndex;
                state = drawState;
            } else if (codepoint == '\n') {
                state = drawState;
            }

            if (state == drawState) {
                textOffsetX = 0;
                textIndex = @as(usize, @intCast(startLine));
                glyphWidth = 0;

                const temp = lastGlyphIndex;
                lastGlyphIndex = glyphCounter - 1;
                glyphCounter = temp;
            }
        } else {
            if (codepoint == '\n') {
                textOffsetY += lineStep;
                textOffsetX = 0;
            } else {
                if (!wordWrap and ((textOffsetX + glyphWidth) > rect.width)) {
                    textOffsetY += lineStep;
                    textOffsetX = 0;
                }

                if ((textOffsetY + baseLineHeight) > rect.height) return false;
            }

            if (wordWrap and (currentEndIndex == endLine)) {
                textOffsetY += lineStep;
                textOffsetX = 0;
                startLine = -1;
                endLine = -1;
                glyphWidth = 0;
                glyphCounter = lastGlyphIndex;
                state = measureState;
                continue;
            }
        }

        if ((textOffsetX != 0) or (codepoint != ' ')) textOffsetX += glyphWidth;
        glyphCounter += 1;
    }

    return true;
}

fn findLineStart(buffer: []const u8, index: usize) usize {
    var i = if (index > buffer.len) buffer.len else index;
    while (i > 0 and buffer[i - 1] != '\n') {
        i -= 1;
    }
    return i;
}

fn findPrevLineStart(buffer: []const u8, current_start: usize) ?usize {
    if (current_start == 0) return null;

    var idx = if (current_start > buffer.len) buffer.len else current_start;
    if (idx > 0) idx -= 1;

    while (idx > 0 and buffer[idx] == '\n') {
        idx -= 1;
    }

    while (idx > 0 and buffer[idx - 1] != '\n') {
        idx -= 1;
    }

    return idx;
}

pub fn drawTextBoxed(
    font: rl.Font,
    text: [:0]const u8,
    rect: rl.Rectangle,
    fontSize: f32,
    spacing: f32,
    wordWrap: bool,
    tint: rl.Color,
    lineSpacing: f32,
) void {
    drawTextBoxedSelectable(
        font,
        text,
        rect,
        fontSize,
        spacing,
        wordWrap,
        tint,
        -1,
        0,
        rl.Color.white,
        rl.Color.white,
        lineSpacing,
    );
}

pub fn drawTextBoxedSelectable(
    font: rl.Font,
    text: [:0]const u8,
    rect: rl.Rectangle,
    fontSize: f32,
    spacing: f32,
    wordWrap: bool,
    tint: rl.Color,
    selectStart: i32,
    selectLength: i32,
    selectTint: rl.Color,
    selectBackTint: rl.Color,
    extraLineSpacing: f32,
) void {
    if (text.len == 0) return;

    const textBytes = text[0..text.len];

    const scaleFactor: f32 = if (font.baseSize == 0) 1 else fontSize / @as(f32, @floatFromInt(font.baseSize));
    const baseLineHeight: f32 = @as(f32, @floatFromInt(font.baseSize)) * scaleFactor;
    const lineStep: f32 = baseLineHeight + extraLineSpacing;

    var textOffsetY: f32 = 0;
    var textOffsetX: f32 = 0;

    const measureState: i32 = 0;
    const drawState: i32 = 1;

    var state: i32 = if (wordWrap) measureState else drawState;
    var startLine: i32 = -1;
    var endLine: i32 = -1;
    var lastGlyphIndex: i32 = -1;

    var selectStartMutable = selectStart;
    const selectLengthConst = selectLength;

    var textIndex: usize = 0;
    var glyphCounter: i32 = 0;
    while (textIndex < textBytes.len) {
        const glyphStartIndex = textIndex;
        var codepointByteCount: i32 = 0;
        const remaining: [:0]const u8 = text[textIndex..];
        const codepoint = rl.getCodepoint(remaining, &codepointByteCount);
        var glyphIndex = rl.getGlyphIndex(font, codepoint);

        if (codepoint == 0x3f) codepointByteCount = 1;
        textIndex += @as(usize, @intCast(codepointByteCount));
        const currentEndIndex = @as(i32, @intCast(textIndex));

        if (glyphIndex < 0) glyphIndex = 0;
        const glyphIndexUsize = @as(usize, @intCast(glyphIndex));

        var glyphWidth: f32 = 0;
        if (codepoint != '\n') {
            const advance = font.glyphs[glyphIndexUsize].advanceX;
            glyphWidth = if (advance == 0)
                font.recs[glyphIndexUsize].width * scaleFactor
            else
                @as(f32, @floatFromInt(advance)) * scaleFactor;

            if (textIndex < textBytes.len) glyphWidth += spacing;
        }

        if (state == measureState) {
            if (startLine < 0) startLine = @as(i32, @intCast(glyphStartIndex));
            if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n') endLine = currentEndIndex;

            if ((textOffsetX + glyphWidth) > rect.width) {
                endLine = if (endLine < 1) currentEndIndex else endLine;
                if (currentEndIndex == endLine) endLine -= codepointByteCount;
                if ((startLine + codepointByteCount) == endLine) endLine = currentEndIndex - codepointByteCount;

                state = drawState;
            } else if (textIndex >= textBytes.len) {
                endLine = currentEndIndex;
                state = drawState;
            } else if (codepoint == '\n') {
                state = drawState;
            }

            if (state == drawState) {
                textOffsetX = 0;
                textIndex = @as(usize, @intCast(startLine));
                glyphWidth = 0;

                const temp = lastGlyphIndex;
                lastGlyphIndex = glyphCounter - 1;
                glyphCounter = temp;
            }
        } else {
            if (codepoint == '\n') {
                textOffsetY += lineStep;
                textOffsetX = 0;
            } else {
                if (!wordWrap and ((textOffsetX + glyphWidth) > rect.width)) {
                    textOffsetY += lineStep;
                    textOffsetX = 0;
                }

                if ((textOffsetY + baseLineHeight) > rect.height) break;

                var glyphSelected = false;
                if ((selectStartMutable >= 0) and (glyphCounter >= selectStartMutable) and (glyphCounter < (selectStartMutable + selectLengthConst))) {
                    rl.drawRectangleRec(
                        .{
                            .x = rect.x + textOffsetX - 1,
                            .y = rect.y + textOffsetY,
                            .width = glyphWidth,
                            .height = @as(f32, @floatFromInt(font.baseSize)) * scaleFactor,
                        },
                        selectBackTint,
                    );
                    glyphSelected = true;
                }

                if ((codepoint != ' ') and (codepoint != '\t')) {
                    rl.drawTextCodepoint(
                        font,
                        codepoint,
                        .{ .x = rect.x + textOffsetX, .y = rect.y + textOffsetY },
                        fontSize,
                        if (glyphSelected) selectTint else tint,
                    );
                }
            }

            if (wordWrap and (currentEndIndex == endLine)) {
                textOffsetY += lineStep;
                textOffsetX = 0;
                startLine = -1;
                endLine = -1;
                glyphWidth = 0;
                selectStartMutable += lastGlyphIndex - glyphCounter;
                glyphCounter = lastGlyphIndex;
                state = measureState;
                continue;
            }
        }

        if ((textOffsetX != 0) or (codepoint != ' ')) textOffsetX += glyphWidth;
        glyphCounter += 1;
    }
}
