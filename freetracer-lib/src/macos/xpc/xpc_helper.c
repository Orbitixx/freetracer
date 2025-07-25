#include "xpc_helper.h"
#include <xpc/xpc.h>

void XPCConnectionSetEventHandler(xpc_connection_t connection,
                                  XPCConnectionHandler connectionHandler,
                                  XPCMessageHandler messageHandler) {
  xpc_connection_set_event_handler(connection, ^(xpc_object_t peer) {
    xpc_type_t type = xpc_get_type(peer);
    if (type == XPC_TYPE_CONNECTION) {
      // Pass the NEW connection (peer), not the listener connection
      connectionHandler(peer, messageHandler);
    }
  });
}

void XPCMessageSetEventHandler(xpc_connection_t connection,
                               XPCMessageHandler msgHandler) {
  xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
    xpc_type_t type = xpc_get_type(event);
    if (type == XPC_TYPE_DICTIONARY) {
      msgHandler(connection, event);
    } else if (type == XPC_TYPE_ERROR) {
      fprintf(stderr, "XPC Connection Error: %s\n", xpc_copy_description(event));
    }
  });
}

void XPCConnectionSendMessageWithReply(xpc_connection_t connection, xpc_object_t msg, dispatch_queue_t queue, XPCMessageHandler msgHandler) {
xpc_connection_send_message_with_reply(
        connection, 
        msg, 
        queue, 
        ^(xpc_object_t reply) {
            // This block will be called when server responds
            msgHandler(connection, reply);
        }
    );
}

void XPCServiceSetEventHandler(xpc_connection_t connection,
                               XPCServiceEventHandler eventHandler) {
  xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
    eventHandler(connection, event);
});

  xpc_connection_resume(connection);
}




void XPCProcessDispatchedEvents() {
    // Process main queue events without blocking
    dispatch_queue_t main_queue = dispatch_get_main_queue();
    dispatch_sync(main_queue, ^{
        // This just ensures any pending main queue work gets processed
    });
}

