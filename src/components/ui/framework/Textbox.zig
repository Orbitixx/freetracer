// Wrappable textbox example from raylib.com
// https://www.raylib.com/examples/text/loader.html?name=text_rectangle_bounds

const std = @import("std");
const rl = @import("raylib");

const Event = @import("./UIEvent.zig");
const UIEvent = Event.UIEvent;

const Transform = @import("./Transform.zig");
const Rectangle = @import("./Rectangle.zig");

const Styles = @import("../Styles.zig");
const RectangleStyle = Styles.RectangleStyle;
const TextStyle = Styles.TextStyle;
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
    wordWrap: bool = true,
};

pub const Selection = struct {
    start: i32,
    length: i32,
};

const Textbox = @This();

allocator: std.mem.Allocator,
transform: Transform,
style: TextboxStyle,
text: [:0]const u8,
font: rl.Font,
params: Params = .{},
selection: ?Selection = null,
background: ?Rectangle = null,

pub fn init(allocator: std.mem.Allocator, text: [:0]const u8, transform: Transform, style: TextboxStyle, background: ?Rectangle, params: Params) Textbox {
    return .{
        .allocator = allocator,
        .transform = transform,
        .background = background,
        .style = style,
        .text = text,
        .font = ResourceManager.getFont(style.text.font),
        .params = params,
    };
}

pub fn start(self: *Textbox) !void {
    self.transform.resolve();
    if (self.background) |*bg| bg.transform.resolve();

    std.debug.print("\nTextbox resolved() Transform in start().", .{});
}

pub fn update(self: *Textbox) !void {
    self.transform.resolve();
    if (self.background) |*bg| bg.transform.resolve();
}

pub fn draw(self: *Textbox) !void {
    if (self.background) |*bg| bg.draw();

    drawTextBoxed(
        self.font,
        self.text,
        self.transform.asRaylibRectangle(),
        self.style.text.fontSize,
        self.style.text.spacing,
        self.params.wordWrap,
        self.style.text.textColor,
        self.style.lineSpacing,
    );
}

pub fn setText(self: *Textbox, text: [:0]const u8) void {
    self.text = text;
}

pub fn setSelection(self: *Textbox, selection: ?Selection) void {
    self.selection = selection;
}

pub fn setWordWrap(self: *Textbox, flag: bool) void {
    self.params.wordWrap = flag;
}

pub fn onEvent(self: *Textbox, event: UIEvent) void {
    _ = self;
    _ = event;
}

pub fn deinit(self: *Textbox) void {
    _ = self;
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
