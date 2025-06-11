const std = @import("std");
const env = @import("../env.zig");
const debug = @import("../lib/util/debug.zig");

const ComponentFramework = @import("../components/framework/import/index.zig");
const Component = ComponentFramework.Component;
const Event = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;
const Registry = ComponentFramework.Registry;

pub const EventManagerSingleton = struct {
    var instance: ?EventManager = null;
    var mutex: std.Thread.Mutex = .{};

    pub const EventManager = struct {
        allocator: std.mem.Allocator,
        subscribers: std.ArrayList(*Component),

        pub fn broadcast(self: *EventManager, event: Event) void {
            for (self.subscribers.items) |component| {
                if (component == event.source) continue;

                _ = component.handleEvent(event) catch |err| {
                    debug.printf(
                        "\nEventManager: error on broadcasting ({any}) event to ({any}) component. {any}.",
                        .{ event, component, err },
                    );
                };
            }
        }

        pub fn subscribe(self: *EventManager, subscriber: *Component) bool {
            self.subscribers.append(subscriber) catch |err| {
                debug.printf("\nEventManager: unable to subscribe component ({any}), error: {any}", .{ subscriber, err });
                return false;
            };

            return true;
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
            .subscribers = std.ArrayList(*Component).init(allocator),
        };
    }

    pub fn broadcast(event: Event) void {
        if (instance != null) {
            instance.?.broadcast(event);
        } else debug.print("Error: Attempted to call EventManager.broadcast() before EventManager is initialized!");
    }

    pub fn subscribe(subscriber: *Component) bool {
        if (instance != null) {
            return instance.?.subscribe(subscriber);
        } else {
            debug.print("Error: Attempted to call EventManager.subscribe() before EventManager is initialized!");
            return false;
        }
    }

    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*inst| {
            inst.subscribers.deinit();
        }

        instance = null;
    }
};
