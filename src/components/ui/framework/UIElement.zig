const std = @import("std");
const Debug = @import("freetracer-lib").Debug;

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const Rectangle = UIFramework.Rectangle;
const View = UIFramework.View;
const Text = UIFramework.Text;
const Textbox = UIFramework.Textbox;
const Texture = UIFramework.Texture;
const DeviceSelectBox = UIFramework.DeviceSelectBox;
const DeviceSelectBoxList = UIFramework.DeviceSelectBoxList;
const FileDropzone = UIFramework.FileDropzone;
const SpriteButton = UIFramework.SpriteButton;
const ProgressBox = UIFramework.ProgressBox;
const UIEvent = UIFramework.UIEvent;

pub const StateChangeHandler = struct {
    function: ?*const fn (ctx: *anyopaque, flag: bool) void = null,
    context: ?*anyopaque = null,

    pub fn call(self: StateChangeHandler, flag: bool) void {
        if (self.context == null or self.function == null) {
            Debug.log(.WARNING, "StateChangeHandler called on instance [handler.call()] with null context. Call aborted.", .{});
            return;
        }

        if (self.context) |ctx| if (self.function) |handler| handler(ctx, flag);
    }
};

pub const ClickHandler = struct {
    function: *const fn (ctx: *anyopaque) void,
    context: *anyopaque,

    pub fn call(self: ClickHandler) void {
        self.function(self.context);
    }
};

pub const DropHandler = struct {
    function: *const fn (ctx: *anyopaque, path: []const u8) void,
    context: *anyopaque,

    pub fn call(self: DropHandler, path: []const u8) void {
        self.function(self.context, path);
    }
};

pub const UIElementCallbacks = struct {
    onStateChange: ?StateChangeHandler = null,
    onClick: ?ClickHandler = null,
    onDrop: ?DropHandler = null,
};

pub const UIElement = union(enum) {
    Rectangle: Rectangle,
    View: View,
    Text: Text,
    Textbox: Textbox,
    Texture: Texture,
    DeviceSelectBox: DeviceSelectBox,
    DeviceSelectBoxList: DeviceSelectBoxList,
    FileDropzone: FileDropzone,
    SpriteButton: SpriteButton,
    ProgressBox: ProgressBox,
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
                        //
                        // if target identifer is specified...
                        //
                        if (ev.target) |target| {
                            // std.debug.print("\nUIElement.onEvent.StateChanged: target does not match element.target; aborting.", .{});
                            if (target != element.identifier) return;

                            if (element.callbacks.onStateChange) |onStateChange| {
                                if (onStateChange.function) |handler| handler(element, ev.isActive) else Debug.log(
                                    .ERROR,
                                    "UIElement.onEvent(): onStateChanger handler (function) is NULL! Aborting.",
                                    .{},
                                );
                            } else {
                                element.active = ev.isActive;
                            }

                            // if target identifier is NOT specified
                        } else {
                            if (element.callbacks.onStateChange) |onStateChange| {
                                Debug.log(
                                    .DEBUG,
                                    "UIElement.onEvent.StateChanged: target not set, executing setActive function. Responding element: {any}",
                                    .{@TypeOf(element)},
                                );
                                if (onStateChange.function) |handler| handler(element, ev.isActive) else Debug.log(
                                    .ERROR,
                                    "UIElement.onEvent(): onStateChanger handler (function) is NULL! Aborting.",
                                    .{},
                                );
                            } else element.active = ev.isActive;
                        }
                    },
                    inline else => {
                        // std.debug.print("\nUIElement.onEvent (other) invoked.", .{});
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
