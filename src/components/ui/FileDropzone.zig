// const std = @import("std");
// const rl = @import("raylib");
//
// extern fn rl_drag_is_hovering() bool;
//
// const Debug = @import("freetracer-lib").Debug;
//
// const Layout = @import("Layout.zig");
// const Primitives = @import("Primitives.zig");
// const TexturePrimitive = Primitives.Texture;
// const Text = Primitives.Text;
//
// const Button = @import("Button.zig");
//
// const ResourceManagerImport = @import("../../managers/ResourceManager.zig");
// const TextureResource = ResourceManagerImport.TEXTURE;
//
// pub const FileDropzone = @This();
//
// const FILE_DRAG_AND_DROP_STRING = "Drag & Drop File Here";
//
// /// Visual configuration for the dropzone.
// pub const Style = struct {
//     backgroundColor: rl.Color,
//     hoverBackgroundColor: rl.Color,
//     borderColor: rl.Color,
//     hoverBorderColor: rl.Color,
//     dashLength: f32 = 8,
//     gapLength: f32 = 8,
//     borderThickness: f32 = 2,
//     cornerRadius: f32 = 0,
//     cornerSegments: i32 = 12,
//     iconScale: f32 = 0.6,
// };
//
// pub const DropHandler = struct {
//     function: *const fn (ctx: *anyopaque, path: []const u8) void,
//     context: *anyopaque,
//
//     pub fn call(self: DropHandler, path: []const u8) void {
//         self.function(self.context, path);
//     }
// };
//
// pub const Callbacks = struct {
//     onClick: Button.ButtonHandler,
//     onDrop: ?DropHandler = null,
// };
//
// frame: *Layout.Bounds,
// style: Style,
// callbacks: Callbacks,
// icon: TexturePrimitive,
// hover: bool = false,
// drag: bool = false,
// dropText: Text,
// resolvedBounds: Primitives.Transform,
// layoutDirty: bool = false,
// cursorActive: bool = false,
//
// pub fn init(frame: *Layout.Bounds, iconResource: TextureResource, style: Style, callbacks: Callbacks) FileDropzone {
//     const resolved = frame.resolve();
//     var icon = TexturePrimitive.init(iconResource, resolved.getPosition());
//     icon.transform.scale = style.iconScale;
//     icon.tint = rl.Color.white;
//
//     var dropzone = FileDropzone{
//         .frame = frame,
//         .style = style,
//         .callbacks = callbacks,
//         .icon = icon,
//         .dropText = Text.init(FILE_DRAG_AND_DROP_STRING, resolved.getPosition(), .{
//             .font = .JERSEY10_REGULAR,
//             .fontSize = 24,
//             .textColor = rl.Color.light_gray,
//         }),
//         .resolvedBounds = resolved,
//     };
//
//     const iconWidth = dropzone.icon.transform.getWidth();
//     const iconHeight = dropzone.icon.transform.getHeight();
//     dropzone.icon.transform.x = resolved.x + (resolved.w / 2) - iconWidth / 2;
//     dropzone.icon.transform.y = resolved.y + (resolved.h / 2) - iconHeight / 2;
//     dropzone.icon.transform.rotation = 0;
//
//     dropzone.updateDropTextPosition();
//
//     return dropzone;
// }
//
// pub fn setStyle(self: *FileDropzone, style: Style) void {
//     self.style = style;
//     self.icon.transform.scale = style.iconScale;
//     self.layoutDirty = true;
// }
//
// pub fn update(self: *FileDropzone) void {
//     const bounds = self.frame.resolve();
//     const boundsChanged = bounds.x != self.resolvedBounds.x or
//         bounds.y != self.resolvedBounds.y or
//         bounds.w != self.resolvedBounds.w or
//         bounds.h != self.resolvedBounds.h;
//
//     self.resolvedBounds = bounds;
//     const rect = bounds.asRaylibRectangle();
//
//     const mouse = rl.getMousePosition();
//     self.hover = rl.checkCollisionPointRec(mouse, rect);
//     self.drag = rl_drag_is_hovering();
//
//     const wantsCursor = self.hover or self.drag;
//     if (wantsCursor and !self.cursorActive) {
//         rl.setMouseCursor(.pointing_hand);
//         self.cursorActive = true;
//     } else if (!wantsCursor and self.cursorActive) {
//         rl.setMouseCursor(.default);
//         self.cursorActive = false;
//     }
//
//     if (self.hover and rl.isMouseButtonPressed(.left)) {
//         self.callbacks.onClick.function(self.callbacks.onClick.context);
//     }
//
//     if (rl.isFileDropped()) {
//         const dropped = rl.loadDroppedFiles();
//         defer rl.unloadDroppedFiles(dropped);
//
//         if (dropped.count > 0 and self.hover) {
//             if (self.callbacks.onDrop) |handler| {
//                 const pathSlice = std.mem.span(dropped.paths[0]);
//                 if (pathSlice.len > 0) {
//                     handler.function(handler.context, pathSlice);
//                 }
//             }
//         }
//     }
//
//     const needsLayout = boundsChanged or self.layoutDirty;
//
//     if (needsLayout) {
//         self.icon.transform.scale = self.style.iconScale;
//
//         const iconWidth = self.icon.transform.getWidth();
//         const iconHeight = self.icon.transform.getHeight();
//
//         self.icon.transform.x = bounds.x + (bounds.w / 2) - iconWidth / 2;
//         self.icon.transform.y = bounds.y + (bounds.h / 2) - iconHeight / 2;
//         self.icon.transform.rotation = 0;
//
//         self.updateDropTextPosition();
//
//         self.layoutDirty = false;
//     }
// }
//
// pub fn draw(self: *FileDropzone) void {
//     const rect = self.resolvedBounds.asRaylibRectangle();
//     const highlight = self.hover or self.drag;
//
//     rl.drawRectangleRec(rect, if (highlight) self.style.hoverBackgroundColor else self.style.backgroundColor);
//
//     const borderColor = if (highlight) self.style.hoverBorderColor else self.style.borderColor;
//
//     drawDashedBorder(
//         rect,
//         borderColor,
//         self.style.borderThickness,
//         self.style.dashLength,
//         self.style.gapLength,
//         self.style.cornerRadius,
//         self.style.cornerSegments,
//     );
//
//     self.icon.tint = if (highlight) rl.Color.init(255, 255, 255, 120) else rl.Color.white;
//     self.icon.draw();
//
//     if (highlight) self.dropText.draw();
// }
//
// fn drawDashedBorder(
//     rect: rl.Rectangle,
//     color: rl.Color,
//     thickness: f32,
//     dashLength: f32,
//     gapLength: f32,
//     cornerRadius: f32,
//     segments: i32,
// ) void {
//     _ = cornerRadius;
//     _ = segments;
//
//     const dash = @max(dashLength, 1.0);
//     const gap = @max(gapLength, 0);
//     const step = dash + gap;
//     var progress: f32 = 0;
//     const perimeter = 2 * (rect.width + rect.height);
//
//     while (progress < perimeter) {
//         const startPoint = pointAlongRect(rect, progress);
//         const endProgress = @min(progress + dash, perimeter);
//         const endPoint = pointAlongRect(rect, endProgress);
//         rl.drawLineEx(startPoint, endPoint, thickness, color);
//         progress += step;
//     }
// }
//
// fn updateDropTextPosition(self: *FileDropzone) void {
//     const textDims = self.dropText.getDimensions();
//     self.dropText.transform.x = self.resolvedBounds.x + (self.resolvedBounds.w - textDims.width) / 2;
//     self.dropText.transform.y = self.resolvedBounds.y + (self.resolvedBounds.h - textDims.height) / 2;
// }
//
// fn pointAlongRect(rect: rl.Rectangle, distance: f32) rl.Vector2 {
//     var remaining = distance;
//     const top = rect.width;
//     const right = rect.height;
//     const bottom = rect.width;
//     const left = rect.height;
//
//     if (remaining <= top) {
//         return .{ .x = rect.x + remaining, .y = rect.y };
//     }
//     remaining -= top;
//
//     if (remaining <= right) {
//         return .{ .x = rect.x + rect.width, .y = rect.y + remaining };
//     }
//     remaining -= right;
//
//     if (remaining <= bottom) {
//         return .{ .x = rect.x + rect.width - remaining, .y = rect.y + rect.height };
//     }
//     remaining -= bottom;
//
//     if (remaining <= left) {
//         return .{ .x = rect.x, .y = rect.y + rect.height - remaining };
//     }
//
//     return .{ .x = rect.x, .y = rect.y };
// }
