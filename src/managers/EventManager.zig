//! EventManager - Thread-safe component event distribution system
//!
//! Provides publish-subscribe event routing between application components.
//! All events are routed through a central event manager that maintains subscriber registry.
//!
//! Threading Model:
//! - Singleton instance protected by global mutex
//! - All public functions acquire mutex for thread-safe access
//! - HashMap protected during all read and write operations
//! - Safe for multi-threaded component communication
//!
//! Component Lifecycle:
//! - Components must call subscribe() before receiving events
//! - Components must call unsubscribe() before being deallocated
//! - Failure to unsubscribe leaves dangling pointers in registry
//! - Event routing fails gracefully for missing subscribers
//!
//! Event Flow:
//! 1. Component calls subscribe(name, self) to register for events
//! 2. Other components call signal(name, event) for targeted delivery
//! 3. Or call broadcast(event) to send to all subscribers
//! 4. Subscribers must call unsubscribe(name) before deallocation
//! 5. EventManager.deinit() at application shutdown
//! ==========================================================================
const std = @import("std");
const Debug = @import("freetracer-lib").Debug;
const env = @import("../env.zig");

const ComponentFramework = @import("../components/framework/import/index.zig");
const Component = ComponentFramework.Component;
const Event = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;
const Registry = ComponentFramework.Registry;

/// Type alias for component name hashes
pub const ComponentHash = u64;

/// Error type for event manager - uses any error from component handlers
pub const EventManagerError = error{
    /// Attempted to initialize EventManager when instance already exists
    AlreadyInitialized,

    /// EventManager not initialized; must call init() first
    NotInitialized,

    /// Failed to locate target subscriber for signal
    SubscriberNotFound,

    /// Failed to subscribe component (likely allocation failure)
    SubscriptionFailed,

    /// Failed to unsubscribe component
    UnsubscriptionFailed,
};

/// Computes hash for component name at compile time.
/// Used as key in subscriber registry.
pub fn hashComponentName(comptime componentName: []const u8) ComponentHash {
    return comptime @as(ComponentHash, std.hash_map.hashString(componentName));
}

/// EventManager singleton providing publish-subscribe event distribution.
/// Thread-safe with mutex protection on all operations.
pub const EventManagerSingleton = struct {
    /// Component name string constants used for event routing
    pub const ComponentName = struct {
        pub const FILE_PICKER = "file_picker";
        pub const FILE_PICKER_UI = "file_picker_ui";
        pub const DEVICE_LIST = "device_list";
        pub const DEVICE_LIST_UI = "device_list_ui";
        pub const DATA_FLASHER = "data_flasher";
        pub const DATA_FLASHER_UI = "data_flasher_ui";
        pub const PRIVILEGED_HELPER = "privileged_helper";
    };

    /// Creates fully qualified event name from component and event names.
    pub fn createEventName(comptime componentName: []const u8, comptime eventName: []const u8) []const u8 {
        return componentName ++ "." ++ eventName;
    }

    /// Internal event manager implementation
    const EventManager = struct {
        allocator: std.mem.Allocator,
        /// Map of component name hashes to component pointers
        subscribers: std.AutoHashMap(ComponentHash, *Component),

        /// Registers a subscriber for event routing.
        /// Component pointer must remain valid until unsubscribe() called.
        ///
        /// `Arguments`:
        ///   name: Component identifier
        ///   subscriber: Pointer to component (must be valid lifetime)
        ///
        /// `Returns`: EventManagerError.SubscriptionFailed on error
        fn subscribe(self: *EventManager, comptime name: []const u8, subscriber: *Component) EventManagerError!void {
            self.subscribers.put(hashComponentName(name), subscriber) catch |err| {
                Debug.log(.ERROR, "EventManager: Failed to subscribe component: {any}", .{err});
                return EventManagerError.SubscriptionFailed;
            };
        }

        /// Unregisters a subscriber from event routing.
        /// Must be called before component is deallocated.
        ///
        /// `Arguments`:
        ///   name: Component identifier to remove
        ///
        /// `Returns`: EventManagerError.SubscriberNotFound if not registered
        fn unsubscribe(self: *EventManager, comptime name: []const u8) EventManagerError!void {
            if (self.subscribers.remove(hashComponentName(name))) {
                return;
            } else {
                Debug.log(.WARNING, "EventManager: Attempted to unsubscribe component that was not registered", .{});
                return EventManagerError.UnsubscriptionFailed;
            }
        }

        /// Routes an event to a specific named subscriber.
        /// Event is delivered only to the target component.
        ///
        /// `Arguments`:
        ///   recipientName: Target component identifier
        ///   event: Event object to deliver
        ///
        /// `Returns`: EventResult from recipient, or error if not found
        fn signal(self: *EventManager, comptime recipientName: []const u8, event: Event) !EventResult {
            const target = self.subscribers.get(hashComponentName(recipientName));

            if (target) |component| {
                return component.handleEvent(event);
            } else {
                Debug.log(.WARNING, "EventManager: Signal target not found: {s}", .{recipientName});
                return EventManagerError.SubscriberNotFound;
            }
        }

        /// Broadcasts an event to all registered subscribers.
        /// Skips sender component unless overrideNotifySelfOnSelfOrigin is true.
        /// Continues broadcasting even if some subscribers error.
        ///
        /// `Note`: Broadcasts are delivered without lock held to prevent deadlocks
        /// when components broadcast events from within event handlers.
        ///
        /// `Arguments`:
        ///   event: Event object to broadcast
        fn broadcast(self: *EventManager, event: Event) void {
            var iter = self.subscribers.iterator();

            while (iter.next()) |entry| {
                const component = entry.value_ptr.*;

                // Skip self if event has source and self-notification is disabled
                if (event.source) |source| {
                    if (component == source and !event.flags.overrideNotifySelfOnSelfOrigin) {
                        continue;
                    }
                }

                // Deliver event, log but don't fail on errors
                _ = component.handleEvent(event) catch |err| {
                    Debug.log(
                        .WARNING,
                        "EventManager: Component error during broadcast: {any}",
                        .{err},
                    );
                };
            }
        }
    };

    var mutex: std.Thread.Mutex = .{};
    var instance: ?EventManager = null;
    var isInitialized: bool = false;

    /// Initializes the EventManager singleton.
    /// Must be called exactly once at application startup.
    ///
    /// `Arguments`:
    ///   allocator: Memory allocator for subscriber registry. Must remain valid for app lifetime.
    ///
    /// `Returns`: EventManagerError.AlreadyInitialized if init() called more than once
    pub fn init(allocator: std.mem.Allocator) EventManagerError!void {
        mutex.lock();
        defer mutex.unlock();

        if (isInitialized) {
            Debug.log(.ERROR, "EventManager.init() called but already initialized", .{});
            return EventManagerError.AlreadyInitialized;
        }

        instance = .{
            .allocator = allocator,
            .subscribers = std.AutoHashMap(ComponentHash, *Component).init(allocator),
        };

        isInitialized = true;
        Debug.log(.INFO, "EventManager: Initialization complete", .{});
    }

    /// Registers a component to receive routed events.
    /// Component must remain valid until unsubscribe() is called.
    ///
    /// `Arguments`:
    ///   subscriberName: Component identifier for event routing
    ///   subscriber: Pointer to component (must not be freed before unsubscribe)
    ///
    /// `Returns`: EventManagerError if subscription fails
    pub fn subscribe(comptime subscriberName: []const u8, subscriber: *Component) EventManagerError!void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*eventManager| {
            return eventManager.subscribe(subscriberName, subscriber);
        } else {
            Debug.log(.ERROR, "EventManager.subscribe() called before initialization", .{});
            return EventManagerError.NotInitialized;
        }
    }

    /// Unregisters a component from receiving events.
    /// Must be called before component is deallocated.
    ///
    /// `Arguments`:
    ///   subscriberName: Component identifier to unsubscribe
    ///
    /// `Returns`: EventManagerError if subscriber not found
    pub fn unsubscribe(comptime subscriberName: []const u8) EventManagerError!void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*eventManager| {
            return eventManager.unsubscribe(subscriberName);
        } else {
            Debug.log(.ERROR, "EventManager.unsubscribe() called before initialization", .{});
            return EventManagerError.NotInitialized;
        }
    }

    /// Routes an event to a specific named component.
    /// Only the target component receives the event.
    ///
    /// `Note`: Lock is released before calling handleEvent to prevent deadlocks
    /// when components route events from within event handlers.
    ///
    /// `Arguments`:
    ///   recipientName: Target component identifier
    ///   event: Event object to deliver
    ///
    /// `Returns`: EventResult from recipient or error if not found
    pub fn signal(comptime recipientName: []const u8, event: Event) !EventResult {
        // Get target subscriber while holding lock
        var targetComponent: ?*Component = null;
        {
            mutex.lock();
            defer mutex.unlock();

            if (instance) |*eventManager| {
                targetComponent = eventManager.subscribers.get(hashComponentName(recipientName));
            }
        }

        // Deliver to target without holding lock to prevent deadlocks
        if (targetComponent) |component| {
            return component.handleEvent(event);
        } else {
            if (instance != null) {
                Debug.log(.WARNING, "EventManager: Signal target not found: {s}", .{recipientName});
            } else {
                Debug.log(.ERROR, "EventManager.signal() called before initialization", .{});
            }
            return EventManagerError.SubscriberNotFound;
        }
    }

    /// Broadcasts an event to all registered subscribers.
    /// Skips the event source component unless explicitly overridden.
    /// Continues delivery even if some subscribers error.
    ///
    /// `Note`: Lock is released before calling handleEvent to prevent deadlocks
    /// when components broadcast events from within event handlers.
    ///
    /// `Arguments`:
    ///   event: Event object to distribute
    pub fn broadcast(event: Event) void {
        // Check initialization and get instance reference while holding lock
        var eventManager: ?*EventManager = null;
        {
            mutex.lock();
            defer mutex.unlock();

            if (instance) |*inst| {
                eventManager = inst;
            }
        }

        // Broadcast without holding lock to prevent deadlocks
        if (eventManager) |em| {
            em.broadcast(event);
        } else {
            Debug.log(.WARNING, "EventManager.broadcast() called before initialization", .{});
        }
    }

    /// Checks if EventManager has been successfully initialized.
    /// Use this to verify initialization before relying on event routing.
    ///
    /// `Returns`: true if init() succeeded and completed
    pub fn isReady() bool {
        mutex.lock();
        defer mutex.unlock();
        return isInitialized and instance != null;
    }

    /// Deinitializes the EventManager and cleans up all resources.
    /// Must be called once at application shutdown.
    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*eventManager| {
            eventManager.subscribers.deinit();
            instance = null;
        }

        isInitialized = false;
        Debug.log(.INFO, "EventManager: Deinitialization complete", .{});
    }
};
