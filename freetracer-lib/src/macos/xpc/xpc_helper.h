#ifndef XPC_HELPER_H
#define XPC_HELPER_H

#include <xpc/xpc.h>


typedef void (*Logger)(int, const char*);
typedef void (*XPCMessageHandler)(xpc_connection_t, xpc_object_t);
typedef void (*XPCConnectionHandler)(xpc_object_t connection, XPCMessageHandler handler);
typedef void (*XPCServiceEventHandler)(xpc_connection_t, xpc_object_t);

void XPCServiceSetEventHandler(xpc_connection_t, XPCServiceEventHandler);

void XPCConnectionSetEventHandler(xpc_connection_t connection,
                                  XPCConnectionHandler connectionHandler,
				  XPCMessageHandler messageHandler);

void XPCMessageSetEventHandler(xpc_connection_t connection, XPCMessageHandler msgHandler);

void XPCProcessDispatchedEvents();

void XPCConnectionSendMessageWithReply(xpc_connection_t connection, xpc_object_t msg, dispatch_queue_t queue, XPCMessageHandler msgHandler);

bool XPCSecurityValidateConnection(xpc_object_t message);

#endif
