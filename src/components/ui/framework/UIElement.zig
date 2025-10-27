const std = @import("std");
const Debug = @import("freetracer-lib").Debug;

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const Rectangle = UIFramework.Rectangle;
const View = UIFramework.View;
const Text = UIFramework.Text;
const Textbox = UIFramework.Textbox;
const Texture = UIFramework.Texture;
const TexturedCheckbox = UIFramework.TexturedCheckbox;
const DeviceSelectBox = UIFramework.DeviceSelectBox;
const DeviceSelectBoxList = UIFramework.DeviceSelectBoxList;
const FileDropzone = UIFramework.FileDropzone;
const SpriteButton = UIFramework.SpriteButton;
const ProgressBox = UIFramework.ProgressBox;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const MAX_CHILDREN = UIFramework.UIEventImport.MAX_VIEW_EVENT_EXEMPT_CHILDREN;

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

pub const SizeChangeHandler = struct {
    function: *const fn (ctx: *anyopaque, size: UIFramework.SizeSpec) void,
    context: *anyopaque,

    pub fn call(self: SizeChangeHandler, size: UIFramework.SizeSpec) void {
        self.function(self.context, size);
    }
};

pub const UIElementCallbacks = struct {
    onStateChange: ?StateChangeHandler = null,
    onClick: ?ClickHandler = null,
    onDrop: ?DropHandler = null,
    onSizeChange: ?SizeChangeHandler = null,
};

pub const UIElement = union(enum) {
    Rectangle: Rectangle,
    View: View,
    Text: Text,
    Textbox: Textbox,
    Texture: Texture,
    TexturedCheckbox: TexturedCheckbox,
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
        // Not a pretty block, nesting is unfortunately necessary for captures
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
                            if (target != element.identifier) return;

                            if (element.callbacks.onStateChange) |onStateChange| {
                                if (onStateChange.function) |handler| handler(element, ev.isActive);
                            } else {
                                // To avoid flickering when element is activated
                                element.transform.resolve();
                                element.active = ev.isActive;
                            }

                            // if target identifier is NOT specified
                        } else {
                            if (isElementInArray(element.identifier, ev.except)) return;
                            const isInverted = isElementInArray(element.identifier, ev.invert);

                            if (element.callbacks.onStateChange) |onStateChange| {

                                // To avoid flickering when element is activated
                                element.transform.resolve();
                                if (onStateChange.function) |handler| handler(element, if (isInverted) !ev.isActive else ev.isActive);
                            } else {
                                // To avoid flickering when element is activated
                                element.transform.resolve();
                                element.active = if (isInverted) !ev.isActive else ev.isActive;
                            }
                        }
                    },
                    .SizeChanged => |ev| {
                        if (ev.target != element.identifier) return;

                        if (element.callbacks.onSizeChange) |handler| handler.function(element, ev.size) else {
                            element.transform.size = ev.size;
                        }
                    },
                    inline else => {
                        @constCast(element).onEvent(event);
                    },
                }
            },
        }
    }

    pub fn transformPtr(self: *UIElement) *Transform {
        return switch (self.*) {
            inline else => |*el| &el.transform,
        };
    }
};

pub fn isElementInArray(ownId: ?UIElementIdentifier, children: ?[MAX_CHILDREN]UIElementIdentifier) bool {
    if (ownId == null) return false;

    if (children) |affectedChildren| {
        for (affectedChildren) |id| {
            if (id == .ZeroElement) break; // Stop at first null (sentinel)
            if (ownId == id) return true;
        }
    }

    return false;
}
