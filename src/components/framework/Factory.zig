// const imports = @import("./import/index.zig");
//
// const Component = imports.Component;
// const ComponentState = imports.ComponentState;
// const Worker = imports.Worker;
//
// const GenericComponent = imports.GenericComponent;
//
// pub fn ComponentFactory(comptime StateType: type) type {
//     return struct {
//         const Self = @This();
//
//         // Function types for component methods
//         pub const InitFn = fn (*Component(StateType)) anyerror!void;
//         pub const DeinitFn = fn (*Component(StateType)) void;
//         pub const UpdateFn = fn (*Component(StateType)) anyerror!void;
//         pub const DrawFn = fn (*Component(StateType)) anyerror!void;
//         pub const RunFn = fn (*Worker(StateType)) void;
//
//         // Default implementations
//         fn defaultInit(_: *Component(StateType)) anyerror!void {}
//         fn defaultDeinit(_: *Component(StateType)) void {}
//         fn defaultUpdate(_: *Component(StateType)) anyerror!void {}
//         fn defaultDraw(_: *Component(StateType)) anyerror!void {}
//
//         // Create a new component with the given methods
//         pub fn create(
//             state: *ComponentState(StateType),
//             init_fn: ?InitFn,
//             deinit_fn: ?DeinitFn,
//             update_fn: ?UpdateFn,
//             draw_fn: ?DrawFn,
//             context: ?*anyopaque,
//         ) Component(StateType) {
//             const vtable = &Component(StateType).VTable{
//                 .init_fn = init_fn orelse defaultInit,
//                 .deinit_fn = deinit_fn orelse defaultDeinit,
//                 .update_fn = update_fn orelse defaultUpdate,
//                 .draw_fn = draw_fn orelse defaultDraw,
//             };
//
//             return Component(StateType).init(state, vtable, context);
//         }
//
//         // Create a worker for this component
//         pub fn createWorker(
//             state: *ComponentState(StateType),
//             run_fn: RunFn,
//         ) Worker(StateType) {
//             return Worker(StateType).init(state, run_fn);
//         }
//
//         // Convert to a generic component interface
//         pub fn asGenericComponent(component: *Component(StateType)) GenericComponent {
//             const vtable = &GenericComponent.VTable{
//                 .init_fn = struct {
//                     fn wrapper(ptr: *anyopaque) anyerror!void {
//                         const comp: *Component(StateType) = @ptrCast(@alignCast(ptr));
//                         return comp.initComponent();
//                     }
//                 }.wrapper,
//                 .deinit_fn = struct {
//                     fn wrapper(ptr: *anyopaque) void {
//                         const comp: *Component(StateType) = @ptrCast(@alignCast(ptr));
//                         comp.deinit();
//                     }
//                 }.wrapper,
//                 .update_fn = struct {
//                     fn wrapper(ptr: *anyopaque) anyerror!void {
//                         const comp: *Component(StateType) = @ptrCast(@alignCast(ptr));
//                         return comp.update();
//                     }
//                 }.wrapper,
//                 .draw_fn = struct {
//                     fn wrapper(ptr: *anyopaque) anyerror!void {
//                         const comp: *Component(StateType) = @ptrCast(@alignCast(ptr));
//                         return comp.draw();
//                     }
//                 }.wrapper,
//             };
//
//             return GenericComponent.init(component, vtable);
//         }
//     };
// }
