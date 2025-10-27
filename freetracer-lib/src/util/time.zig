// Deterministic and runtime time utilities used for logging timestamps and
// simple delays without tying call-sites directly to std.time internals.
const std = @import("std");

extern "c" fn localtime(t: *const std.c.time_t) ?*tm;
extern "c" fn gmtime(t: *const std.c.time_t) ?*tm;

const tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
};

/// Normalized representation of a civil timestamp used in debug logging.
pub const DateTime = struct {
    month: u4,
    day: u5,
    hours: u5,
    minutes: u6,
    seconds: u6,
    year: u16,
    format: [:0]const u8 = "{d:0>2}/{d:0>2}/{d} {d:0>2}:{d:0>2}:{d:0>2}",

    pub fn eql(self: DateTime, other: DateTime) bool {
        return self.year == other.year and
            self.month == other.month and
            self.day == other.day and
            self.hours == other.hours and
            self.minutes == other.minutes and
            self.seconds == other.seconds;
    }
};

/// Converts a Unix timestamp into a DateTime struct, applying a UTC offset.
/// This function is deterministic and testable.
///
/// Parameters:
/// - timestamp: The number of seconds since the Unix epoch.
/// - utcCorrectionHours: The hour offset from UTC (e.g., -5 for EST).
pub fn fromTimestamp(timestamp: i64, utcCorrectionHours: i8) DateTime {
    // Add timezone offset directly to the initial timestamp.
    const offset_seconds = @as(i64, utcCorrectionHours) * 3600;
    const adjusted_timestamp = timestamp + offset_seconds;

    // Clamp to Unix epoch minimum to avoid wrap-around when the adjusted timestamp
    // would become negative (which triggers a safety panic when casting to u64).
    const clamped_timestamp: i64 = if (adjusted_timestamp < 0) 0 else adjusted_timestamp;

    // Create an EpochSeconds instance from the adjusted timestamp.
    // We use u64 as required by std.time.epoch, handling potential negative results
    // from the adjustment by casting. The underlying logic in std.time handles this.
    const datetime = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(clamped_timestamp)) };

    // Calculate the year, month, day, and time components.
    const year_day = datetime.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = datetime.getDaySeconds();

    return DateTime{
        .seconds = day_seconds.getSecondsIntoMinute(),
        .minutes = day_seconds.getMinutesIntoHour(),
        .hours = @as(u5, @intCast(day_seconds.getHoursIntoDay())),
        .day = month_day.day_index + 1,
        .month = month_day.month.numeric(),
        .year = year_day.year,
    };
}

/// Detects the system's local UTC offset in hours, accounting for DST.
/// Returns the offset as an i8 (e.g., -5 for EST, -4 for EDT, 1 for CET).
/// Defaults to 0 if detection fails.
pub fn getLocalUTCOffset() i8 {
    var now_timestamp: std.c.time_t = @intCast(std.time.timestamp());
    const local_time = localtime(&now_timestamp);

    if (local_time != null) {
        const gmt_time = gmtime(&now_timestamp);
        if (gmt_time != null) {
            const local = local_time.?.*;
            const gmt = gmt_time.?.*;

            const local_secs: i64 = local.tm_hour * 3600 + local.tm_min * 60 + local.tm_sec;
            var gmt_secs: i64 = gmt.tm_hour * 3600 + gmt.tm_min * 60 + gmt.tm_sec;

            if (local.tm_mday != gmt.tm_mday) {
                if (local.tm_mday > gmt.tm_mday) {
                    gmt_secs -= 86400;
                } else {
                    gmt_secs += 86400;
                }
            }

            const diff_secs = local_secs - gmt_secs;
            const hours = @divTrunc(diff_secs, 3600);
            return @as(i8, @intCast(hours));
        }
    }

    return 0;
}

/// Returns the current DateTime, adjusted for the system's local UTC offset.
/// This function is non-deterministic as it depends on the system clock.
pub fn now() DateTime {
    return fromTimestamp(std.time.timestamp(), getLocalUTCOffset());
}

// Test block for the fromTimestamp function.
test "DateTime fromTimestamp conversion with UTC offsets" {
    const testing = std.testing;

    // Test Case 1: A known timestamp at UTC (0 offset).
    // Timestamp corresponds to 2023-01-01 00:00:00 UTC.
    const timestamp1: i64 = 1672531200;
    const expected1 = DateTime{
        .year = 2023,
        .month = 1,
        .day = 1,
        .hours = 0,
        .minutes = 0,
        .seconds = 0,
    };

    const actual1 = fromTimestamp(timestamp1, 0);
    try testing.expectEqual(expected1, actual1);

    // Test Case 2: The same timestamp with a positive UTC offset.
    // We expect the time to be 7 hours ahead.
    const expected2 = DateTime{
        .year = 2023,
        .month = 1,
        .day = 1,
        .hours = 7,
        .minutes = 0,
        .seconds = 0,
    };

    const actual2 = fromTimestamp(timestamp1, 7);
    try testing.expectEqual(expected2, actual2);

    // Test Case 3: A negative UTC offset that crosses a day and year boundary.
    // UTC time is 2023-01-01 00:00:00.
    // In UTC-5 (EST), it should be the previous day: 2022-12-31 19:00:00.
    const expected3 = DateTime{
        .year = 2022,
        .month = 12,
        .day = 31,
        .hours = 19,
        .minutes = 0,
        .seconds = 0,
    };

    const actual3 = fromTimestamp(timestamp1, -5);
    try testing.expectEqual(expected3, actual3);
}
