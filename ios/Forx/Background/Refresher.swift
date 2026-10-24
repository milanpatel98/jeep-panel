import BackgroundTasks
import Foundation
import os
import UserNotifications

// MARK: - Alert state (pure, tested)

/// Alerts to notify now: active now, not active at the last refresh, and switched on.
/// An alert that clears and comes back notifies again.
nonisolated func newAlerts(
    active: Set<Alert>, previouslyActive: Set<Alert>, enabled: Set<Alert> = Set(Alert.allCases)
) -> Set<Alert> {
    active.subtracting(previouslyActive).intersection(enabled)
}

/// When the Jeep was first seen unlocked: kept while it stays unlocked, cleared once it's
/// locked, kept as is when the lock state is unknown. The snapshot has no gear, so every
/// unlocked refresh counts as parked.
nonisolated func nextUnlockedSince(_ since: Date?, locked: Bool?, now: Date) -> Date? {
    switch locked {
    case false?: since ?? now
    case true?: nil
    case nil: since
    }
}

/// Only a snapshot read by this refresh is evaluated, not the cached one shown again.
nonisolated func isNewSnapshot(previous: JeepSnapshot?, current: JeepSnapshot) -> Bool {
    current.updatedAt != previous?.updatedAt
}

/// The notification copy.
nonisolated func alertText(_ alert: Alert, snapshot: JeepSnapshot) -> String {
    switch alert {
    case .leftUnlocked:
        return "Your Jeep is unlocked"
    case .lowTire:
        let order = ["FL", "FR", "RL", "RR"]
        let lowest = order.compactMap { key in snapshot.tiresPsi[key].map { (key, $0) } }
            .min { $0.1 < $1.1 }  // `min` keeps the first of equal values: FL, FR, RL, RR
        guard let lowest else { return "Low tire pressure" }
        return "Low tire pressure: \(cornerName(lowest.0)) \(lowest.1) psi"
    case .lowRange:
        guard let miles = snapshot.rangeMiles else { return "Low range" }
        return "Low range: \(miles) mi left"
    case .chargingDone:
        return "Charging done"
    }
}

private nonisolated func cornerName(_ key: String) -> String {
    switch key {
    case "FL": "front left"
    case "FR": "front right"
    case "RL": "rear left"
    case "RR": "rear right"
    default: key
    }
}

/// The Settings toggles: UserDefaults `alerts.<rawValue>`, on unless switched off.
nonisolated enum AlertSettings {
    static func key(_ alert: Alert) -> String { "alerts.\(alert.rawValue)" }

    static func isOn(_ alert: Alert, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key(alert)) as? Bool ?? true
    }

    static func enabled(in defaults: UserDefaults) -> Set<Alert> {
        Set(Alert.allCases.filter { isOn($0, in: defaults) })
    }
}

/// What the background refresh remembers between runs, in UserDefaults:
/// `alerts.active` (raw values active at the last refresh) and `unlocked.since`.
nonisolated struct AlertTracker {
    static let activeKey = "alerts.active"
    static let unlockedSinceKey = "unlocked.since"

    let defaults: UserDefaults

    /// A background refresh: records it and returns the alerts to notify, in `Alert.allCases` order.
    func update(previous: JeepSnapshot?, current: JeepSnapshot, now: Date) -> [Alert] {
        let active = activeAlerts(previous: previous, current: current, now: now)
        let fresh = newAlerts(
            active: active, previouslyActive: storedActive, enabled: AlertSettings.enabled(in: defaults))
        storedActive = active
        return Alert.allCases.filter(fresh.contains)
    }

    /// Any refresh (also the foreground ones, which never notify): tracks `unlocked.since` and
    /// drops alerts that are no longer active, but never adds one, so the next background
    /// run still sees a newly active alert as new and notifies.
    func observe(previous: JeepSnapshot?, current: JeepSnapshot, now: Date) {
        let active = activeAlerts(previous: previous, current: current, now: now)
        storedActive = storedActive.intersection(active)
    }

    /// Updates `unlocked.since` for this reading, then evaluates the rules.
    private func activeAlerts(previous: JeepSnapshot?, current: JeepSnapshot, now: Date) -> Set<Alert> {
        let stored = defaults.object(forKey: Self.unlockedSinceKey) as? Date
        let since = nextUnlockedSince(stored, locked: current.locked, now: now)
        if let since {
            defaults.set(since, forKey: Self.unlockedSinceKey)
        } else {
            defaults.removeObject(forKey: Self.unlockedSinceKey)
        }
        return Set(alerts(previous: previous, current: current, unlockedSince: since, now: now))
    }

    private var storedActive: Set<Alert> {
        get { Set((defaults.stringArray(forKey: Self.activeKey) ?? []).compactMap(Alert.init(rawValue:))) }
        nonmutating set { defaults.set(Alert.allCases.filter(newValue.contains).map(\.rawValue), forKey: Self.activeKey) }
    }

    /// Forgets the tracked state (on sign-out).
    func reset() {
        defaults.removeObject(forKey: Self.activeKey)
        defaults.removeObject(forKey: Self.unlockedSinceKey)
    }
}

// MARK: - Background refresh

/// Wakes the app in the background (`com.milanpatel.Forx.refresh`, earliest every 15 min),
/// reads the Jeep and posts a notification per new alert. Never prompts: no Face ID, no UI.
enum Refresher {
    static let taskID = "com.milanpatel.Forx.refresh"
    static let interval: TimeInterval = 15 * 60

    private static let logger = Logger(subsystem: "com.milanpatel.Forx", category: "refresh")
    private static var store: JeepStore?

    /// Registers the task handler. Call once, before the app finishes launching.
    static func register(store: JeepStore) {
        self.store = store
        // Every new reading, foreground or background, keeps the tracker current.
        store.onSnapshot = { previous, current in
            AlertTracker(defaults: .standard).observe(previous: previous, current: current, now: Date())
        }
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { @Sendable task in
            let box = TaskBox(task: task)
            Task { @MainActor in Refresher.handle(box.task) }
        }
        if !ok { logger.error("Background refresh handler not registered") }
    }

    /// Asks iOS for the next background refresh, no sooner than 15 min from now.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGTask) {
        schedule()  // the next one, whatever happens to this one
        guard let store else {
            task.setTaskCompleted(success: false)
            return
        }
        let done = Completion(task: task)
        let work = Task { @MainActor in
            let previous = store.lastKnownSnapshot
            await store.refresh()
            guard !Task.isCancelled else { return }
            if !store.needsSignIn, let current = store.snapshot,
               isNewSnapshot(previous: previous, current: current) {
                let fresh = AlertTracker(defaults: .standard).update(previous: previous, current: current, now: Date())
                for alert in fresh {
                    await post(alert, snapshot: current)
                }
            }
            done.finish(success: true)
        }
        task.expirationHandler = { @Sendable in
            Task { @MainActor in
                work.cancel()
                done.finish(success: false)
            }
        }
    }

    private static func post(_ alert: Alert, snapshot: JeepSnapshot) async {
        let content = UNMutableNotificationContent()
        content.body = alertText(alert, snapshot: snapshot)
        content.sound = .default
        // One per kind: a newer one replaces the old one in Notification Center.
        let request = UNNotificationRequest(
            identifier: "\(taskID).\(alert.rawValue)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Notification not posted: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Asks once for permission to post alerts (after the first sign-in).
    static func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Calls `setTaskCompleted` exactly once.
    private final class Completion {
        private let task: BGTask
        private var finished = false

        init(task: BGTask) {
            self.task = task
        }

        func finish(success: Bool) {
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
        }
    }
}

/// Carries the system's `BGTask` from the scheduler's queue to the main actor.
private nonisolated struct TaskBox: @unchecked Sendable {
    let task: BGTask
}

/// Asks iOS to wake the app for a background refresh (`com.milanpatel.Forx.refresh`).
/// Called when the app goes to the background.
func scheduleBackgroundRefresh() {
    Refresher.schedule()
}
