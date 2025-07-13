const std = @import("std");
const env = @import("../../env.zig");

pub const DateTime = struct {
    month: u4,
    day: u5,
    hours: u5,
    minutes: u6,
    seconds: u6,
    year: u16,
    format: [:0]const u8 = "{d:0>2}/{d:0>2}/{d} {d:0>2}:{d:0>2}:{d:0>2}",
};

pub fn now() DateTime {
    const timestamp = std.time.timestamp();
    const epoch_seconds = @as(u64, @intCast(timestamp));

    const utcCorrectionHours = env.UTC_CORRECTION_HOURS;

    // Convert to datetime
    const datetime = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const year_day = datetime.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = datetime.getDaySeconds();

    const utcHours = day_seconds.getHoursIntoDay();
    var hours: i8 = @intCast(day_seconds.getHoursIntoDay());
    var day = month_day.day_index + 1;
    var month = month_day.month.numeric();
    var year = year_day.year;

    std.debug.assert(@abs(utcCorrectionHours) < 24);

    if (utcHours >= @abs(utcCorrectionHours)) hours += utcCorrectionHours;

    if (utcHours <= @abs(utcCorrectionHours)) {
        const diff: i8 = @intCast(@abs(utcCorrectionHours) - utcHours);
        hours = 24 - diff;

        if (day == 1) {
            day = 0;
            if (month == 1) {
                month = 12;
                year -= 1;
            } else month -= 1;
        } else day -= 1;
    }

    return DateTime{
        .seconds = day_seconds.getSecondsIntoMinute(),
        .minutes = day_seconds.getMinutesIntoHour(),
        .hours = @intCast(@abs(hours)),
        .day = day,
        .month = month,
        .year = year,
    };
}
