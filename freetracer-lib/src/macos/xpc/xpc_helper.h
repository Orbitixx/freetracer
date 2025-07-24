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


#endif
