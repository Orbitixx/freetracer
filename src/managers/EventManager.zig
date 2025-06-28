const std = @import("std");
const env = @import("../env.zig");
const debug = @import("../lib/util/debug.zig");

const ComponentFramework = @import("../components/framework/import/index.zig");
const Component = ComponentFramework.Component;
const Event = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;
const Registry = ComponentFramework.Registry;

pub const ComponentHash = u64;

pub fn hashComponentName(comptime componentName: []const u8) ComponentHash {
    return comptime @as(ComponentHash, std.hash_map.hashString(componentName));
}

// TODO: Mutex is perhaps improperly/haphazardly being used here: e.g. instance is accessed without locking the singleton.
pub const EventManagerSingleton = struct {
    var instance: ?EventManager = null;
    var mutex: std.Thread.Mutex = .{};

    pub const EventManager = struct {
        allocator: std.mem.Allocator,
        subscribers: std.AutoHashMap(ComponentHash, *Component),

        pub fn subscribe(self: *EventManager, comptime name: []const u8, subscriber: *Component) bool {
            self.subscribers.put(hashComponentName(name), subscriber) catch |err| {
                debug.printf("\nEventManager: unable to subscribe component ({any}), error: {any}", .{ subscriber, err });
                return false;
            };

            return true;
        }

        pub fn signal(self: *EventManager, comptime receipientName: []const u8, event: Event) !EventResult {
            const target = self.subscribers.get(hashComponentName(receipientName));

            if (target) |*component| {
                return component.handleEvent(event);
            } else {
                return error.EventManagerDidNotLocateCalledSubscriber;
            }
        }

        pub fn broadcast(self: *EventManager, event: Event) void {
            var iter = self.subscribers.iterator();

            while (iter.next()) |component| {
                if (component.value_ptr.* == event.source and event.flags.overrideNotifySelfOnSelfOrigin == false) continue;

                _ = component.value_ptr.*.handleEvent(event) catch |err| {
                    debug.printf(
                        "\nEventManager: error on broadcasting ({any}) event to ({any}) component. {any}.",
                        .{ event, component.value_ptr, err },
                    );
                };
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) !void {
        mutex.lock();
        defer mutex.unlock();

        if (instance != null) {
            std.log.err("Error: attempted to re-initialize an existing EventManager singleton instance.", .{});
            return;
        }

        instance = .{
            .allocator = allocator,
            .subscribers = std.AutoHashMap(ComponentHash, *Component).init(allocator),
        };
    }

    /// Puts a *Component pointer into the EventManager.instance.subscribers AutoHashMap
    /// as <ComponentHash (u64), *Component> key-value pair.
    /// Returns a boolean as indicator of successful subscription.
    pub fn subscribe(comptime subscriberName: []const u8, subscriber: *Component) bool {
        //
        if (instance) |*eventManager| {
            return eventManager.subscribe(subscriberName, subscriber);
        } else {
            debug.print("Error: Attempted to call EventManager.subscribe() before EventManager is initialized!");
            return false;
        }
    }

    /// Sends an Event object to a single Component recipient with the indicated name (as u64 hash).
    /// Returns an error or an EventResult object.
    pub fn signal(comptime recipientName: []const u8, event: Event) !EventResult {
        if (instance) |*eventManager| {
            return eventManager.signal(recipientName, event);
        } else {
            debug.print("Error: Attempted to call EventManager.broadcast() before EventManager is initialized!");
            return error.EventManagerCallBeforeInstanceInitialized;
        }
    }

    /// Distributes an Event object to all subscribers, except self.
    /// Can override the self-notification exemption by flipping a flag in the event object:
    /// event.flags.overrideNotifySelfOnSelfOrigin = true;
    /// Returns void.
    pub fn broadcast(event: Event) void {
        //
        if (instance) |*eventManager| {
            return eventManager.broadcast(event);
        } else debug.print("Error: Attempted to call EventManager.broadcast() before EventManager is initialized!");
    }

    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*eventManager| {
            eventManager.subscribers.deinit();
        }

        instance = null;
    }
};
