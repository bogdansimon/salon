import Foundation

/// "New artwork once per calendar day at a set time."
public struct DailySchedule: Sendable {
    public var time: TimeOfDay
    public var calendar: Calendar

    public init(time: TimeOfDay, calendar: Calendar = .current) {
        self.time = time
        self.calendar = calendar
    }

    /// Today's change instant if it has passed, otherwise yesterday's.
    public func mostRecentChange(atOrBefore now: Date) -> Date {
        let today = changeInstant(on: now)
        return today <= now ? today : calendar.date(byAdding: .day, value: -1, to: today)!
    }

    /// The next change instant strictly after `now`.
    public func nextChange(after now: Date) -> Date {
        let today = changeInstant(on: now)
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// True when the wallpaper hasn't changed since the most recent scheduled instant.
    public func isChangeDue(lastChange: Date?, now: Date) -> Bool {
        guard let lastChange else { return true }
        return lastChange < mostRecentChange(atOrBefore: now)
    }

    private func changeInstant(on day: Date) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)!
    }
}

/// Retry delays after failed fetches: 15 min, 30 min, 1 h, 2 h, then every 4 h.
public enum RetryBackoff {
    public static let first: TimeInterval = 15 * 60
    public static let maximum: TimeInterval = 4 * 3600

    public static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        return min(first * pow(2, Double(failures - 1)), maximum)
    }
}
