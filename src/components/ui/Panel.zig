const rl = @import("raylib");

const Layout = @import("./Layout.zig");
const Primitives = @import("./Primitives.zig");

const Rectangle = Primitives.Rectangle;
const Text = Primitives.Text;

/// Describes the visual properties applied to a panel-like container.
pub const Appearance = struct {
    width: f32,
    backgroundColor: rl.Color,
    borderColor: rl.Color,
    headerColor: rl.Color,
};

/// References to the primitives that make up a panel container.
pub const Elements = struct {
    /// Optional layout bounds that own the rectangle dimensions.
    frame: ?*Layout.Bounds = null,
    rect: *Rectangle,
    header: *Text,
};

/// Applies the given appearance to the provided panel elements.
/// Handles both layout-managed and standalone rectangles.
pub fn applyAppearance(elements: Elements, appearance: Appearance) void {
    if (elements.frame) |frame| {
        frame.size.width = Layout.UnitValue.pixels(appearance.width);
        elements.rect.transform = frame.resolve();
    } else {
        elements.rect.transform.w = appearance.width;
    }

    elements.rect.style.color = appearance.backgroundColor;
    elements.rect.style.borderStyle.color = appearance.borderColor;
    elements.header.style.textColor = appearance.headerColor;
}
