#include "xpc_helper.h"
#include <xpc/xpc.h>

// void XPCConnectionSetEventHandler(xpc_connection_t connection,
//                                   XPCConnectionHandler connectionHandler,
//                                   XPCMessageHandler messageHandler) {
//   xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
//     xpc_type_t type = xpc_get_type(event);
//
//     if (type == XPC_TYPE_CONNECTION) {
//       connectionHandler(event, messageHandler);
//     }
//   });
// }
//
// void XPCMessageSetEventHandler(xpc_connection_t connection,
//                                XPCMessageHandler msgHandler) {
//   xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
//     msgHandler(event);
//   });
//
//   xpc_connection_resume(connection);
// }

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
      // Handle connection errors
      fprintf(stderr, "XPC Connection Error: %s\n", xpc_copy_description(event));
    }
  });
  // Don't call resume here - let the caller handle it
}

void XPCServiceSetEventHandler(xpc_connection_t connection,
                               XPCServiceEventHandler eventHandler) {
  xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
    eventHandler(connection, event);
});

  xpc_connection_resume(connection);
}

// void XPCClientSetEventHandler(xpc_connection_t connection,
//                                   XPCConnectionHandler connectionHandler,
//                                   XPCMessageHandler messageHandler) {
// 	xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
//         // Handle async errors (like connection problems)
//         if (xpc_get_type(event) == XPC_TYPE_ERROR) {
//             fprintf(stderr, "XPC Error: %s\n", xpc_copy_description(event));
//         }
//     });
// }
