const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const Rectangle = UIFramework.Rectangle;
const View = UIFramework.View;
const Text = UIFramework.Text;
const Textbox = UIFramework.Textbox;
const Texture = UIFramework.Texture;
const FileDropzone = UIFramework.FileDropzone;
const SpriteButton = UIFramework.SpriteButton;
const UIEvent = UIFramework.UIEvent;

pub const UIElement = union(enum) {
    Rectangle: Rectangle,
    View: View,
    Text: Text,
    Textbox: Textbox,
    Texture: Texture,
    FileDropzone: FileDropzone,
    SpriteButton: SpriteButton,
    // Button: Button,
    // SpriteButton: SpriteButton,

    pub fn start(self: *UIElement) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).start(),
        }
    }

    pub fn update(self: *UIElement) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).update(),
        }
    }

    pub fn draw(self: *UIElement) anyerror!void {
        switch (self.*) {
            inline else => |*element| try @constCast(element).draw(),
        }
    }

    pub fn deinit(self: *UIElement) void {
        switch (self.*) {
            inline else => |*element| @constCast(element).deinit(),
        }
    }

    pub fn onEvent(self: *UIElement, event: UIEvent) void {
        switch (self.*) {
            inline else => |*element| @constCast(element).onEvent(event),
        }
    }

    pub fn transformPtr(self: *UIElement) *Transform {
        return switch (self.*) {
            // .View => |*v| &v.transform,
            // .Text => |*t| &t.transform,
            // .Textbox => |*tb| &tb.transform,
            // .Texture => |*tex| &tex.transform,
            // .FileDropzone => |*fdz| &fdz.transform,
            inline else => |*el| &el.transform,
        };
    }
};
