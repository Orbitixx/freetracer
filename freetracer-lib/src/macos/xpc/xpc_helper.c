#include "xpc_helper.h"
// #include <xpc/xpc.h>
//

int testMath(int a, int b) {
	return a + b;
}

// static void handle_event(xpc_object_t event) {
//     if (xpc_get_type(event) == XPC_TYPE_DICTIONARY) {
//         // Print received message
//         const char* received_message = xpc_dictionary_get_string(event, "message");
//         printf("Received message: %s\n", received_message);
//
//         // Create a response dictionary
//         xpc_object_t response = xpc_dictionary_create(NULL, NULL, 0);
//         xpc_dictionary_set_string(response, "received", "received");
//
//         // Send response
//         xpc_connection_t remote = xpc_dictionary_get_remote_connection(event);
//         xpc_connection_send_message(remote, response);
//
//         // Clean up
//         xpc_release(response);
//     }
// }
//
// static void handle_connection(xpc_connection_t connection) {
//     xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
//         handle_event(event);
//     });
//     xpc_connection_resume(connection);
// }
//
// void start_xpc_server() {
//     xpc_connection_t service = xpc_connection_create_mach_service("com.orbitixx.freetracer-helper",
//                                                                    dispatch_get_main_queue(),
//                                                                    XPC_CONNECTION_MACH_SERVICE_LISTENER);
//     if (!service) {
//         fprintf(stderr, "Failed to create service.\n");
//         exit(EXIT_FAILURE);
//     }
//
// 	xpc_connection_set_event_handler(service, ^(xpc_object_t event) {
//         	xpc_type_t type = xpc_get_type(event);
//         	if (type == XPC_TYPE_CONNECTION) {
//         	    handle_connection(event);
//         	}
//     	});
//
//     xpc_connection_resume(service);
//     dispatch_main();
// }


