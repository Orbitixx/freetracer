const std = @import("std");
const osd = @import("osdialog");
const json = std.json;

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const SeverityLevel = freetracer_lib.Debug.SeverityLevel;

pub const PreferenceError = error{
    AlreadyInitialized,
    NotInitialized,
    IoFailure,
    PathTooLong,
};

pub const PreferenceKey = enum {
    CheckUpdates,
    DebugLevel,
};

const Defaults = struct {
    pub const checkUpdates = false;
    pub const debugLevel = SeverityLevel.DEBUG;
};

const Preferences = struct {
    checkUpdates: bool = Defaults.checkUpdates,
    debugLevel: SeverityLevel = Defaults.debugLevel,
};

const FilePayload = struct {
    checkUpdates: ?bool = null,
    debugLevel: ?u8 = null,
};

const PreferencesManager = struct {
    allocator: std.mem.Allocator,
    data: Preferences = .{},
    pathBuffer: [std.fs.max_path_bytes]u8 = undefined,
    pathLen: usize = 0,
    isFirstLaunch: bool = false,

    fn getPath(self: *const PreferencesManager) [:0]const u8 {
        return self.pathBuffer[0..self.pathLen :0];
    }

    fn init(allocator: std.mem.Allocator, path: [:0]const u8) !PreferencesManager {
        var manager = PreferencesManager{
            .allocator = allocator,
        };

        manager.pathBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
        if (path.len >= manager.pathBuffer.len) return PreferenceError.PathTooLong;
        @memcpy(manager.pathBuffer[0..path.len], path);
        manager.pathBuffer[path.len] = 0;
        manager.pathLen = path.len;

        try manager.loadOrCreate();

        return manager;
    }

    fn loadOrCreate(self: *PreferencesManager) !void {
        self.data = .{};
        try self.ensureDirectoryExists();

        const file = std.fs.openFileAbsolute(self.getPath(), .{ .mode = .read_only }) catch |err| switch (err) {
            std.fs.File.OpenError.FileNotFound => {
                self.isFirstLaunch = true;
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

        if (parsed.value.debugLevel) |value| {
            if (value <= @intFromEnum(SeverityLevel.ERROR)) {
                self.data.debugLevel = @enumFromInt(value);
            }
        }
    }

    fn ensureDirectoryExists(self: *PreferencesManager) !void {
        const dir_path = std.fs.path.dirname(self.getPath()) orelse return;

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

        const path_str = self.getPath();
        Debug.log(.DEBUG, "PreferencesManager.persist: attempting to create/update file at path: {s}", .{path_str});

        const dir_path = std.fs.path.dirname(path_str) orelse {
            Debug.log(.ERROR, "PreferencesManager.persist: unable to determine directory from path: {s}", .{path_str});
            return PreferenceError.IoFailure;
        };
        const file_name = std.fs.path.basename(path_str);

        var dir = std.fs.openDirAbsolute(dir_path, .{}) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: failed to open directory {s}: {any}", .{ dir_path, err });
            return PreferenceError.IoFailure;
        };
        defer dir.close();

        var file = dir.openFile(file_name, .{ .mode = .write_only }) catch |err| switch (err) {
            std.fs.File.OpenError.FileNotFound => {
                // File doesn't exist yet, create it
                _ = dir.createFile(file_name, .{}) catch |create_err| {
                    Debug.log(.ERROR, "PreferencesManager: failed to create preferences file: {any}", .{create_err});
                    return PreferenceError.IoFailure;
                };
                return try self.persist();
            },
            else => {
                Debug.log(.ERROR, "PreferencesManager: failed to open preferences file: {any}", .{err});
                return PreferenceError.IoFailure;
            },
        };
        defer file.close();

        try file.setEndPos(0);

        const payload = json.Stringify.valueAlloc(self.allocator, .{
            .checkUpdates = self.data.checkUpdates,
            .debugLevel = @intFromEnum(self.data.debugLevel),
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

pub fn init(allocator: std.mem.Allocator, absolutePath: [:0]const u8) !bool {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) return PreferenceError.AlreadyInitialized;

    const manager = try PreferencesManager.init(allocator, absolutePath);
    instance = manager;

    return manager.isFirstLaunch;
}

pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();
    instance = null;
}

pub fn getCheckUpdatesPermission() bool {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        Debug.log(.DEBUG, "getCheckUpdatesPermission: instance path length: {d}", .{inst.pathLen});

        const allowUpdateChecking = osd.message(
            "Allow Freetracer to check for updates on github.com?\n\nNote: update check is performed once upon app startup. Updates are strongly recommended for application and system security.",
            .{ .buttons = .yes_no, .level = .info },
        );

        inst.data.checkUpdates = allowUpdateChecking;
        inst.persist() catch |err| {
            Debug.log(.ERROR, "Unable to save user preference: {any}", .{err});
            _ = osd.message("Failed to save user preference. Please consider reporting as a bug.", .{ .buttons = .ok, .level = .err });
        };
        inst.isFirstLaunch = false;
        return allowUpdateChecking;
    }

    return false;
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

pub fn getDebugLevel() !SeverityLevel {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| {
        return inst.data.debugLevel;
    }
    return PreferenceError.NotInitialized;
}

pub fn setDebugLevel(value: SeverityLevel) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.data.debugLevel != value) {
            inst.data.debugLevel = value;
            try inst.persist();
        }
        return;
    }
    return PreferenceError.NotInitialized;
}

pub fn getPath() ![:0]const u8 {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| return inst.getPath();
    return PreferenceError.NotInitialized;
}
