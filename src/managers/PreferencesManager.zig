const std = @import("std");
const json = std.json;

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

pub const PreferenceError = error{
    AlreadyInitialized,
    NotInitialized,
    IoFailure,
    PathTooLong,
};

pub const PreferenceKey = enum {
    CheckUpdates,
};

const Defaults = struct {
    pub const checkUpdates = false;
};

const Preferences = struct {
    checkUpdates: bool = Defaults.checkUpdates,
};

const FilePayload = struct {
    checkUpdates: ?bool = null,
};

const PreferencesManager = struct {
    allocator: std.mem.Allocator,
    data: Preferences = .{},
    pathBuffer: [std.fs.max_path_bytes]u8 = undefined,
    path: [:0]const u8 = "",

    fn init(allocator: std.mem.Allocator, path: [:0]const u8) !PreferencesManager {
        var manager = PreferencesManager{
            .allocator = allocator,
        };

        manager.pathBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
        if (path.len >= manager.pathBuffer.len) return PreferenceError.PathTooLong;
        @memcpy(manager.pathBuffer[0..path.len], path);
        manager.path = manager.pathBuffer[0..path.len :0];

        try manager.loadOrCreate();

        return manager;
    }

    fn loadOrCreate(self: *PreferencesManager) !void {
        self.data = .{};
        try self.ensureDirectoryExists();

        const file = std.fs.openFileAbsoluteZ(self.path, .{ .mode = .read_only }) catch |err| switch (err) {
            std.fs.File.OpenError.FileNotFound => {
                try self.persist();
                return;
            },
            else => {
                Debug.log(.ERROR, "PreferencesManager: failed to open preferences file: {any}", .{err});
                return PreferenceError.IoFailure;
            },
        };
        defer file.close();

        const contents = file.readToEndAlloc(self.allocator, 16 * 1024) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: unable to read preferences: {any}", .{err});
            return PreferenceError.IoFailure;
        };
        defer self.allocator.free(contents);

        if (contents.len == 0) {
            Debug.log(.WARNING, "PreferencesManager: preferences file empty, using defaults.", .{});
            try self.persist();
            return;
        }

        const parsed = json.parseFromSlice(FilePayload, self.allocator, contents, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: failed to parse preferences, reverting to defaults. Error: {any}", .{err});
            try self.persist();
            return;
        };
        defer parsed.deinit();

        if (parsed.value.checkUpdates) |value| {
            self.data.checkUpdates = value;
        }
    }

    fn ensureDirectoryExists(self: *PreferencesManager) !void {
        const dir_path = std.fs.path.dirname(self.path) orelse return;

        std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                Debug.log(.ERROR, "PreferencesManager: failed to ensure directory {s}: {any}", .{ dir_path, err });
                return PreferenceError.IoFailure;
            },
        };
    }

    fn persist(self: *PreferencesManager) !void {
        try self.ensureDirectoryExists();

        var file = std.fs.createFileAbsoluteZ(self.path, .{
            .truncate = true,
            .read = true,
            .mode = 0o600,
        }) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: failed to create preferences file: {any}", .{err});
            return PreferenceError.IoFailure;
        };
        defer file.close();

        const payload = json.Stringify.valueAlloc(self.allocator, .{
            .checkUpdates = self.data.checkUpdates,
        }, .{
            .whitespace = .indent_1,
        }) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: failed to serialize preferences: {any}", .{err});
            return PreferenceError.IoFailure;
        };
        defer self.allocator.free(payload);

        file.writeAll(payload) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: failed to write preferences file: {any}", .{err});
            return PreferenceError.IoFailure;
        };
    }
};

var instance: ?PreferencesManager = null;
var mutex: std.Thread.Mutex = .{};

pub fn init(allocator: std.mem.Allocator, absolute_path: [:0]const u8) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) return PreferenceError.AlreadyInitialized;

    const manager = try PreferencesManager.init(allocator, absolute_path);
    instance = manager;
}

pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();
    instance = null;
}

pub fn getCheckUpdates() !bool {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| {
        return inst.data.checkUpdates;
    }
    return PreferenceError.NotInitialized;
}

pub fn setCheckUpdates(value: bool) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.data.checkUpdates != value) {
            inst.data.checkUpdates = value;
            try inst.persist();
        }
        return;
    }
    return PreferenceError.NotInitialized;
}

pub fn getPath() ![:0]const u8 {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| return inst.path;
    return PreferenceError.NotInitialized;
}
