import AppKit
import SalonCore

/// Fires when the next change is due (every day, 2 days, week or month at the chosen
/// time, counted from the last change), checks at launch and on wake, and retries
/// with backoff after a failure.
@MainActor
final class Scheduler {
    var onDue: (() -> Void)?
    private var timer: Timer?
    private var retryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var schedule = ChangeSchedule(frequency: .daily, time: TimeOfDay(hour: 9, minute: 0))
    /// The last change and the "not before" hold after a schedule edit.
    private var anchors: () -> (lastChange: Date?, notBefore: Date?) = { (nil, nil) }

    func start(schedule: ChangeSchedule, anchors: @escaping () -> (lastChange: Date?, notBefore: Date?)) {
        self.anchors = anchors
        update(schedule: schedule)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAfterLaunchOrWake() }
        }
        checkAfterLaunchOrWake()
    }

    func update(schedule: ChangeSchedule) {
        self.schedule = schedule
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

    /// Call after every change (automatic or by hand) and every schedule edit.
    func scheduleNext() {
        timer?.invalidate()
        timer = nil
        let (lastChange, notBefore) = anchors()
        guard var instant = schedule.dueDate(lastChange: lastChange, notBefore: notBefore) else { return } // paused
        // Already due: a change is in flight or failed (the retry timer covers it).
        // Check again at the next time of day rather than firing in a loop.
        if instant <= Date() { instant = schedule.nextTime(after: Date()) }
        let timer = Timer(fire: instant, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerFired() {
        let (lastChange, notBefore) = anchors()
        if schedule.isChangeDue(lastChange: lastChange, notBefore: notBefore, now: Date()) { onDue?() }
        scheduleNext()
    }

    /// Catches up on a change missed while the Mac was asleep or off.
    private func checkAfterLaunchOrWake() {
        let (lastChange, notBefore) = anchors()
        // First run always hangs something, even when paused.
        if lastChange == nil || schedule.isChangeDue(lastChange: lastChange, notBefore: notBefore, now: Date()) { onDue?() }
        scheduleNext()
    }
}
