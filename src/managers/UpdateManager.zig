const std = @import("std");
const osd = @import("osdialog");
const freetracer_lib = @import("freetracer-lib");
const AppConfig = @import("../config.zig");
const Debug = freetracer_lib.Debug;

const UpdateManagerState = struct {};

const ComponentFramework = @import("../components/framework/import/index.zig");
const State = ComponentFramework.ComponentState(UpdateManagerState);
const Worker = ComponentFramework.Worker(UpdateManagerState);

const WindowManager = @import("./WindowManager.zig").WindowManagerSingleton;
const relY = WindowManager.relH;
const relX = WindowManager.relW;

const UI = @import("../components/ui/Primitives.zig");
const Color = @import("../components/ui/Styles.zig").Color;

const UNKNOWN_STRING: [:0]const u8 = "Unknown";

pub const UpdateManagerSingleton = struct {
    const Self = @This();

    pub const UpdateManagerError = error{
        AlreadyInitialized,
        NotInitialized,
    };

    const ReleaseInfo = struct {
        html_url: [:0]const u8,
        name: [:0]const u8,
        tag_name: [:0]const u8,
        body: [:0]const u8,
    };

    const UpdateManager = struct {
        allocator: std.mem.Allocator,
        newVersion: [:0]const u8 = UNKNOWN_STRING,
        newVersionDescription: [:0]const u8 = UNKNOWN_STRING,
        newVersionUrl: [:0]const u8 = UNKNOWN_STRING,
        response: ?std.json.Parsed(ReleaseInfo) = null,
        enabled: bool = false,

        fn deinit(self: *UpdateManager) void {
            if (self.response) |*parsed| {
                parsed.deinit();
                self.response = null;
            }
        }
    };

    var instance: ?UpdateManager = null;
    var mutex: std.Thread.Mutex = .{};
    var bgRect: UI.Rectangle = undefined;
    var state: State = undefined;
    var worker: ?Worker = null;

    pub fn init(allocator: std.mem.Allocator, enabled: bool, autoStart: bool) !void {
        mutex.lock();
        defer mutex.unlock();

        state = State.init(.{});

        if (instance != null) {
            Debug.log(.ERROR, "UpdateManager.init(): instance already initialized.", .{});
            return UpdateManagerError.AlreadyInitialized;
        }

        instance = UpdateManager{
            .allocator = allocator,
            .enabled = enabled,
        };

        if (enabled) {
            worker = Worker.init(allocator, &state, .{
                .callback_fn = onUpdateCheckFinished,
                .callback_context = &instance,
                .run_fn = onCheckUpdatesRequested,
                .run_context = &instance,
            }, .{});

            if (autoStart) {
                if (worker) |*w| try w.start();
            }
        } else Debug.log(.INFO, "App update check is disabled in ./config/freetraces/preferences.json. Skipping app version check.", .{});
    }

    pub fn update() void {
        if (instance) |inst| {
            if (!inst.enabled) return;
        } else return;

        if (worker) |*w| {
            if (w.status != .NEEDS_JOINING) return;

            w.join();

            if (std.mem.eql(u8, AppConfig.APP_VERSION, instance.?.newVersion)) return;

            var buf = std.mem.zeroes([256]u8);
            const message = std.fmt.bufPrintZ(buf[0..], "A new version of Freetracer ({s}) is available on Github. Download it now?\n\nUpdates are strongly recommended for security purposes.", .{instance.?.newVersion}) catch "A new version of Freetracer is available on Github. Download it now?\n\nUpdates are strongly recommended for security purposes.";

            const shouldUpdate = osd.message(message, .{ .buttons = .yes_no, .level = .info });

            if (shouldUpdate) {
                const argv: []const []const u8 = &.{ "open", latestUrl() };

                if (instance) |inst| {
                    var ch = std.process.Child.init(argv, inst.allocator);
                    ch.spawn() catch return;
                }
            }
        }
    }

    pub fn parseJsonResponse(allocator: std.mem.Allocator, json: []u8) !std.json.Parsed(ReleaseInfo) {
        return try std.json.parseFromSlice(
            ReleaseInfo,
            allocator,
            json,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
    }

    pub fn onUpdateCheckFinished(workerContext: *Worker, context: *anyopaque) void {
        _ = workerContext;
        _ = context;
        Debug.log(.INFO, "UpdateManager called onUpdateCheckFinished() callback.", .{});
    }

    pub fn onCheckUpdatesRequested(workerContext: *Worker, context: *anyopaque) void {
        var self: *UpdateManager = @ptrCast(@alignCast(context));

        var body_writer = std.Io.Writer.Allocating.init(workerContext.allocator);
        defer body_writer.deinit();

        var client: std.http.Client = .{ .allocator = workerContext.allocator };
        defer client.deinit();

        const options = std.http.Client.FetchOptions{
            .location = .{ .url = AppConfig.APP_RELEASES_API_ENDPOINT },
            .method = .GET,
            .response_writer = &body_writer.writer,
        };

        const res = client.fetch(options) catch |err| {
            Debug.log(.ERROR, "UpdateManager worker failed trying to submit a GET HTTP request. Error: {any}", .{err});
            return;
        };

        if (res.status.class() == .success) {
            const body = body_writer.written();

            const response = Self.parseJsonResponse(workerContext.allocator, body) catch |err| {
                Debug.log(.ERROR, "UpdateManager worker failed to parse response JSON data. Error: {any}", .{err});
                return;
            };

            self.response = response;
            self.newVersion = response.value.tag_name;
            self.newVersionDescription = response.value.body;
            self.newVersionUrl = response.value.html_url;

            Debug.log(
                .INFO,
                "UpdateManager:\n\tLatest version: {s}\n\tLatest version desc: {s}\n\tLatest version URL: {s}",
                .{ self.newVersion, self.newVersionDescription[0..@min(20, self.newVersionDescription.len)], self.newVersionUrl },
            );
        } else {
            Debug.log(.ERROR, "fetch() request failed: {s}", .{res.status.phrase().?});
            return;
        }
    }

    pub fn draw() void {}

    pub fn checkForUpdates() void {
        if (instance) |_| if (worker) |*wrk| wrk.start() catch |err| {
            Debug.log(.ERROR, "Failed to performed update check: {any}", .{err});
            _ = osd.message(
                "Freetracer encountered an issue attempting to check for an update.",
                .{ .buttons = .ok, .level = .warning },
            );
        };
    }

    pub fn latestVersion() [:0]const u8 {
        if (instance) |mgr| return mgr.newVersion;
        return UNKNOWN_STRING;
    }

    pub fn latestDescription() [:0]const u8 {
        if (instance) |mgr| return mgr.newVersionDescription;
        return UNKNOWN_STRING;
    }

    pub fn latestUrl() [:0]const u8 {
        if (instance) |mgr| return mgr.newVersionUrl;
        return UNKNOWN_STRING;
    }

    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        worker = null;

        if (instance) |*mgr| {
            mgr.deinit();
            instance = null;
        }
    }
};
