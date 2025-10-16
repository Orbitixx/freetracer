const std = @import("std");

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
        // Not a pretty block, nesting is unfortunately required for captures
        // Basically, this says:
        //  - if the received event is UIEvent.StateChanged; AND
        //      A. the target is specified; AND
        //          - the target is not this element -> THEN
        //              - ignore the event; STOP
        //      B. the target is NOT specified; AND
        //          - the element's setActive optional function is set -> THEN
        //              - call the setActiveFn with its signature arguments; STOP
        //  - for all other types of events, process the event locally in the element; STOP
        switch (self.*) {
            inline else => |*element| {
                switch (event) {
                    .StateChanged => |ev| {
                        if (ev.target) |target| {
                            std.debug.print("\nUIElement.onEvent.StateChanged: target does not match element.target; aborting.", .{});
                            if (target != element.identifier) return;
                        } else {
                            if (element.setActive) |setActiveFn| {
                                std.debug.print("\nUIElement.onEvent.StateChanged: target not set, executing setActive function. Responding element: {any}", .{element});
                                setActiveFn(element, ev.isActive);
                            }
                        }
                    },
                    inline else => {
                        std.debug.print("\nUIElement.onEvent (other) invoked.", .{});
                        @constCast(element).onEvent(event);
                    },
                }
            },
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
