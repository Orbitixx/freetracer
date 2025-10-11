// Objective-C API to bridge a hook for dragging file over NSWindow event
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static _Atomic(bool) gDragHover = false;
bool rl_drag_is_hovering(void) { return gDragHover; }

typedef NSDragOperation (*DragOpIMP)(id, SEL, id<NSDraggingInfo>);
typedef void (*DragVoidIMP)(id, SEL, id<NSDraggingInfo>);
typedef BOOL (*DragBoolIMP)(id, SEL, id<NSDraggingInfo>);

static DragOpIMP orig_draggingEntered = NULL;
static DragOpIMP orig_draggingUpdated = NULL;
static DragVoidIMP orig_draggingExited = NULL;
static DragVoidIMP orig_draggingEnded = NULL;
static DragBoolIMP orig_performDragOperation = NULL;

static NSDragOperation hook_draggingEntered(id self, SEL _cmd,
                                            id<NSDraggingInfo> sender) {
  gDragHover = true;
  if (orig_draggingEntered) {
    return orig_draggingEntered(self, _cmd, sender);
  }
  return NSDragOperationNone;
}

static NSDragOperation hook_draggingUpdated(id self, SEL _cmd,
                                            id<NSDraggingInfo> sender) {
  gDragHover = true;
  if (orig_draggingUpdated) {
    return orig_draggingUpdated(self, _cmd, sender);
  }
  return NSDragOperationNone;
}

static void hook_draggingExited(id self, SEL _cmd, id<NSDraggingInfo> sender) {
  gDragHover = false;
  if (orig_draggingExited) {
    orig_draggingExited(self, _cmd, sender);
  }
}

static BOOL hook_performDragOperation(id self, SEL _cmd,
                                      id<NSDraggingInfo> sender) {
  BOOL result = NO;
  if (orig_performDragOperation) {
    result = orig_performDragOperation(self, _cmd, sender);
  }
  gDragHover = false;
  return result;
}

static void hook_draggingEnded(id self, SEL _cmd, id<NSDraggingInfo> sender) {
  gDragHover = false;
  if (orig_draggingEnded) {
    orig_draggingEnded(self, _cmd, sender);
  }
}

void rl_drag_install_on_nswindow(void *nswindow_ptr) {
  (void)nswindow_ptr;

  static bool installed = false;
  if (installed)
    return;
  installed = true;

  Class viewClass = objc_lookUpClass("GLFWContentView");
  if (!viewClass) {
    return;
  }

  Method method;

  method = class_getInstanceMethod(viewClass, @selector(draggingEntered:));
  if (method) {
    orig_draggingEntered = (DragOpIMP)method_getImplementation(method);
    method_setImplementation(method, (IMP)hook_draggingEntered);
  }

  method = class_getInstanceMethod(viewClass, @selector(draggingUpdated:));
  if (method) {
    orig_draggingUpdated = (DragOpIMP)method_getImplementation(method);
    method_setImplementation(method, (IMP)hook_draggingUpdated);
  }

  method = class_getInstanceMethod(viewClass, @selector(draggingExited:));
  if (method) {
    orig_draggingExited = (DragVoidIMP)method_getImplementation(method);
    method_setImplementation(method, (IMP)hook_draggingExited);
  }

  method = class_getInstanceMethod(viewClass, @selector(draggingEnded:));
  if (method) {
    orig_draggingEnded = (DragVoidIMP)method_getImplementation(method);
    method_setImplementation(method, (IMP)hook_draggingEnded);
  }

  method = class_getInstanceMethod(viewClass, @selector(performDragOperation:));
  if (method) {
    orig_performDragOperation = (DragBoolIMP)method_getImplementation(method);
    method_setImplementation(method, (IMP)hook_performDragOperation);
  }
}
