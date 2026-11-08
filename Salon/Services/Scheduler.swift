import AppKit
import SalonCore

/// Fires once per calendar day at the chosen time, checks at launch and on wake,
/// and retries with backoff after a failure.
@MainActor
final class Scheduler {
    /// A timer that fires this long after its instant (Mac was asleep) counts as "missed".
    private static let missedTolerance: TimeInterval = 15 * 60

    var onDue: (() -> Void)?
    private var timer: Timer?
    private var retryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var schedule = DailySchedule(time: TimeOfDay(hour: 9, minute: 0))
    private var changeOnWake = true
    private var lastChange: () -> Date? = { nil }

    func start(time: TimeOfDay, changeOnWake: Bool, lastChange: @escaping () -> Date?) {
        self.lastChange = lastChange
        update(time: time, changeOnWake: changeOnWake)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAfterLaunchOrWake() }
        }
        checkAfterLaunchOrWake()
    }

    func update(time: TimeOfDay, changeOnWake: Bool) {
        schedule = DailySchedule(time: time)
        self.changeOnWake = changeOnWake
        scheduleNext()
    }

    /// After a failed fetch: try again later (15 min, 30 min, 1 h…).
    func scheduleRetry(afterFailures failures: Int) {
        retryTimer?.invalidate()
        let delay = RetryBackoff.delay(afterFailures: failures)
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDue?() }
        }
    }

    func cancelRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// Minutes until the next retry, for the error card ("try again in 15 minutes").
    var retryMinutes: Int? {
        guard let date = retryTimer?.fireDate else { return nil }
        return max(1, Int((date.timeIntervalSinceNow / 60).rounded()))
    }

    func scheduleNext() {
        timer?.invalidate()
        let instant = schedule.nextChange(after: Date())
        let timer = Timer(fire: instant, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired(scheduledFor: instant) }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerFired(scheduledFor instant: Date) {
        let late = Date().timeIntervalSince(instant) > Self.missedTolerance
        if !late || changeOnWake { onDue?() }
        scheduleNext()
    }

    private func checkAfterLaunchOrWake() {
        let last = lastChange()
        let due = schedule.isChangeDue(lastChange: last, now: Date())
        // First run always hangs something; otherwise honour "change on wake if missed".
        if due && (last == nil || changeOnWake) { onDue?() }
        scheduleNext()
    }
}
