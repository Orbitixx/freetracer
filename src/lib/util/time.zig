const std = @import("std");

pub const DateTime = struct {
    year: i64,
    month: i64,
    days: i64,
    hours: i64,
    minutes: i64,
    seconds: i64,
    milliseconds: i64,
};

// Divisions of a nanosecond.
pub const ns_per_us: i64 = 1000;
pub const ns_per_ms: i64 = 1000 * ns_per_us;
pub const ns_per_s: i64 = 1000 * ns_per_ms;
pub const ns_per_min: i64 = 60 * ns_per_s;
pub const ns_per_hour: i64 = 60 * ns_per_min;
pub const ns_per_day: i64 = 24 * ns_per_hour;
pub const ns_per_week: i64 = 7 * ns_per_day;

pub fn now() DateTime {
    const epochTime = std.time.timestamp();

    std.debug.print("\n\nepoch: {d}\n", .{epochTime});

    const microseconds: i64 = @divTrunc(epochTime, 1000);
    const milliseconds: i64 = @divTrunc(microseconds, 1000);
    const seconds: i64 = @divTrunc(milliseconds, 1000);
    const minutes: i64 = @divTrunc(seconds, 60);
    const hours: i64 = @divTrunc(minutes, 60);
    const days: i64 = @divTrunc(hours, 24);

    return DateTime{
        .milliseconds = milliseconds,
        .seconds = (seconds),
        .minutes = (minutes),
        .hours = (hours),
        .days = (days),
        .month = 12,
        .year = 1970,
    };
}
