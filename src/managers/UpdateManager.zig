const std = @import("std");
const freetracer_lib = @import("freetracer-lib");
const env = @import("../env.zig");
const Debug = freetracer_lib.Debug;

pub const UpdateManagerSingleton = struct {
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
        newVersion: ?[:0]const u8 = null,
        newVersionDescription: ?[:0]const u8 = null,
        newVersionUrl: ?[:0]const u8 = null,
        response: ?std.json.Parsed(ReleaseInfo) = null,

        fn checkUpdates(self: *UpdateManager) !void {
            var body_writer = std.Io.Writer.Allocating.init(self.allocator);
            defer body_writer.deinit();

            var client: std.http.Client = .{ .allocator = self.allocator };
            defer client.deinit();

            const options = std.http.Client.FetchOptions{
                .location = .{ .url = env.APP_RELEASES_API_ENDPOINT },
                .method = .GET,
                .response_writer = &body_writer.writer,
            };

            const res = try client.fetch(options);

            std.debug.print("fetch() status: {any} {s}\n", .{ res.status, res.status.phrase().? });

            if (res.status.class() == .success) {
                const body = body_writer.written();
                try self.parseReleaseInfo(body);
            } else {
                std.debug.print("fetch() request failed: {s}\n\n", .{res.status.phrase().?});
            }

            const version = self.newVersion orelse "unknown";
            const description = self.newVersionDescription orelse "n/a";
            const url = self.newVersionUrl orelse "n/a";

            Debug.log(
                .INFO,
                "\n\nLatest version:\t{s}\nLatest version desc:\t{s}\nLatest version URL:\t{s}\n",
                .{ version, description, url },
            );
        }

        fn parseReleaseInfo(self: *UpdateManager, json: []u8) !void {
            self.clearResponse();

            const parsed = try std.json.parseFromSlice(
                ReleaseInfo,
                self.allocator,
                json,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            );

            self.response = parsed;

            const info = &self.response.?.value;
            self.newVersion = info.tag_name;
            self.newVersionUrl = info.html_url;
            self.newVersionDescription = info.body;
        }

        fn clearResponse(self: *UpdateManager) void {
            if (self.response) |*parsed| {
                parsed.deinit();
                self.response = null;
            }

            self.newVersion = null;
            self.newVersionDescription = null;
            self.newVersionUrl = null;
        }

        fn deinit(self: *UpdateManager) void {
            self.clearResponse();
        }
    };

    var instance: ?UpdateManager = null;
    var mutex: std.Thread.Mutex = .{};

    pub fn init(allocator: std.mem.Allocator) !void {
        mutex.lock();
        defer mutex.unlock();

        if (instance != null) {
            Debug.log(.ERROR, "UpdateManager.init(): instance already initialized.", .{});
            return UpdateManagerError.AlreadyInitialized;
        }

        instance = UpdateManager{
            .allocator = allocator,
        };
    }

    pub fn checkUpdates() !void {
        if (instance) |*mgr| {
            try mgr.checkUpdates();
            return;
        }

        Debug.log(.ERROR, "UpdateManager.checkUpdates(): called before init().", .{});
        return UpdateManagerError.NotInitialized;
    }

    pub fn latestVersion() ?[:0]const u8 {
        if (instance) |mgr| return mgr.newVersion;
        return null;
    }

    pub fn latestDescription() ?[:0]const u8 {
        if (instance) |mgr| return mgr.newVersionDescription;
        return null;
    }

    pub fn latestUrl() ?[:0]const u8 {
        if (instance) |mgr| return mgr.newVersionUrl;
        return null;
    }

    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*mgr| {
            mgr.deinit();
            instance = null;
        }
    }
};
