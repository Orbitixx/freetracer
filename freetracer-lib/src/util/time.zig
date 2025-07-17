const std = @import("std");

pub const DateTime = struct {
    month: u4,
    day: u5,
    hours: u5,
    minutes: u6,
    seconds: u6,
    year: u16,
    format: [:0]const u8 = "{d:0>2}/{d:0>2}/{d} {d:0>2}:{d:0>2}:{d:0>2}",
};

pub fn now(utcCorrectionHours: i8) DateTime {
    const timestamp = std.time.timestamp();
    const epoch_seconds = @as(u64, @intCast(timestamp));

    // Add timezone offset directly to timestamp
    const offset_seconds = @as(i64, utcCorrectionHours) * 3600;
    const adjusted_timestamp = @as(i64, @intCast(epoch_seconds)) + offset_seconds;
    const adjusted_epoch_seconds = @as(u64, @intCast(adjusted_timestamp));

    // Convert adjusted timestamp to datetime
    const datetime = std.time.epoch.EpochSeconds{ .secs = adjusted_epoch_seconds };
    const year_day = datetime.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = datetime.getDaySeconds();

    return DateTime{
        .seconds = day_seconds.getSecondsIntoMinute(),
        .minutes = day_seconds.getMinutesIntoHour(),
        .hours = @intCast(day_seconds.getHoursIntoDay()),
        .day = month_day.day_index + 1,
        .month = month_day.month.numeric(),
        .year = year_day.year,
    };
}
