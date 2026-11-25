import Foundation

/// How often the wallpaper changes on its own (Settings › General › Changing).
public enum ChangeFrequency: String, Codable, CaseIterable, Sendable {
    case daily, everyTwoDays, weekly, monthly, never

    public var title: String {
        switch self {
        case .daily: "Every day"
        case .everyTwoDays: "Every 2 days"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .never: "Never (paused)"
        }
    }
}

/// "A new work every N days (or months) at a set time", counted from the last change.
/// A change made by hand restarts the count.
public struct ChangeSchedule: Sendable {
    public var frequency: ChangeFrequency
    public var time: TimeOfDay
    public var calendar: Calendar

    public init(frequency: ChangeFrequency, time: TimeOfDay, calendar: Calendar = .current) {
        self.frequency = frequency
        self.time = time
        self.calendar = calendar
    }

    /// When the next automatic change is due: nil when paused, `.distantPast` when
    /// nothing has ever been hung. `notBefore` holds it back after a schedule edit.
    public func dueDate(lastChange: Date?, notBefore: Date? = nil) -> Date? {
        guard frequency != .never else { return nil }
        guard let lastChange else { return .distantPast }
        let day = calendar.startOfDay(for: lastChange)
        let nextDay: Date = switch frequency {
        case .daily: calendar.date(byAdding: .day, value: 1, to: day)!
        case .everyTwoDays: calendar.date(byAdding: .day, value: 2, to: day)!
        case .weekly: calendar.date(byAdding: .day, value: 7, to: day)!
        // Jan 31 + 1 month = Feb 28/29.
        case .monthly: calendar.date(byAdding: .month, value: 1, to: day)!
        case .never: day
        }
        let due = changeInstant(on: nextDay)
        guard let notBefore else { return due }
        return max(due, notBefore)
    }

    public func isChangeDue(lastChange: Date?, notBefore: Date? = nil, now: Date) -> Bool {
        guard let due = dueDate(lastChange: lastChange, notBefore: notBefore) else { return false }
        return due <= now
    }

    /// The next time-of-day instant strictly after `now`, whatever the frequency.
    public func nextTime(after now: Date) -> Date {
        let today = changeInstant(on: now)
        return today > now ? today : changeInstant(on: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!)
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
