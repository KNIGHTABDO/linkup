import Foundation

/// Helpers for formatting schedule cadence, next run calculations, and time conversions.
enum ScheduleFormatter {
    static let dayShortNames: [Int: String] = [
        1: "Mon",
        2: "Tue",
        3: "Wed",
        4: "Thu",
        5: "Fri",
        6: "Sat",
        7: "Sun"
    ]

    static let dayFullNames: [Int: String] = [
        1: "Monday",
        2: "Tuesday",
        3: "Wednesday",
        4: "Thursday",
        5: "Friday",
        6: "Saturday",
        7: "Sunday"
    ]

    /// Formats schedule cadence: "Every day at 08:00" or "Mon, Wed, Fri at 18:30".
    static func cadence(time: String, days: [Int]) -> String {
        let t = time.isEmpty ? "08:00" : time
        let sorted = Array(Set(days)).sorted()
        if sorted.isEmpty || sorted.count == 7 {
            return "Every day at \(t)"
        }
        if sorted == [1, 2, 3, 4, 5] {
            return "Weekdays at \(t)"
        }
        if sorted == [6, 7] {
            return "Weekends at \(t)"
        }
        let names = sorted.compactMap { dayShortNames[$0] }
        return "\(names.joined(separator: ", ")) at \(t)"
    }

    /// Converts "HH:MM" string to a Date object today.
    static func dateFromTime(_ time: String) -> Date {
        let parts = time.split(separator: ":")
        var calendar = Calendar.current
        calendar.timeZone = .current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            comps.hour = h
            comps.minute = m
            comps.second = 0
        } else {
            comps.hour = 8
            comps.minute = 0
            comps.second = 0
        }
        return calendar.date(from: comps) ?? Date()
    }

    /// Converts a Date to "HH:MM" string format.
    static func timeFromDate(_ date: Date) -> String {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 8
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    /// Calculates the next occurrence Date based on time string and days array.
    /// In ScheduleInfo: 1 = Monday … 7 = Sunday; empty = every day.
    static func nextRunDate(time: String, days: [Int], from referenceDate: Date = Date()) -> Date? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let targetHour = Int(parts[0]), let targetMinute = Int(parts[1]) else {
            return nil
        }
        var calendar = Calendar.current
        calendar.timeZone = .current
        let activeDays: Set<Int> = days.isEmpty ? Set(1...7) : Set(days)

        for dayOffset in 0..<8 {
            guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: referenceDate) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day, .weekday], from: candidate)
            guard let rawWeekday = comps.weekday else { continue }
            // Calendar: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
            let scheduleDay = rawWeekday == 1 ? 7 : (rawWeekday - 1)

            if activeDays.contains(scheduleDay) {
                comps.hour = targetHour
                comps.minute = targetMinute
                comps.second = 0
                if let targetDate = calendar.date(from: comps), targetDate > referenceDate {
                    return targetDate
                }
            }
        }
        return nil
    }

    /// Relative string for next run (e.g. "in 3 h", "in 15 m", "in 1 d").
    static func relativeNextRun(date: Date, relativeTo now: Date = Date()) -> String {
        let diff = date.timeIntervalSince(now)
        if diff <= 0 {
            return "due now"
        }
        let minutes = Int(round(diff / 60))
        if minutes < 1 {
            return "in < 1 m"
        }
        if minutes < 60 {
            return "in \(minutes) m"
        }
        let hours = Int(round(diff / 3600))
        if hours < 24 {
            return "in \(hours) h"
        }
        let days = Int(round(diff / 86400))
        return "in \(days) d"
    }

    /// Computes the relative next run text for a given schedule.
    static func relativeNextRun(for schedule: ScheduleInfo, now: Date = Date()) -> String? {
        if let ts = schedule.nextRun, ts > 0 {
            return relativeNextRun(date: Date(timeIntervalSince1970: ts), relativeTo: now)
        }
        if let targetDate = nextRunDate(time: schedule.time, days: schedule.days, from: now) {
            return relativeNextRun(date: targetDate, relativeTo: now)
        }
        return nil
    }
}
