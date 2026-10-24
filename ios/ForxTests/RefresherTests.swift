import Foundation
import Testing
@testable import Forx

struct RefresherTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    /// A snapshot that raises nothing on its own.
    private func snap(
        locked: Bool? = true, tires: [String: Int] = ["FL": 35, "FR": 35, "RL": 35, "RR": 35],
        range: Int? = 186, pluggedIn: Bool? = false, charging: Bool? = false, at: Date? = nil,
        ignition: Bool? = nil
    ) -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: locked, doorsOpen: [], tailgateOpen: nil,
            rangeMiles: range, fuelPercent: nil, evPercent: nil, pluggedIn: pluggedIn,
            charging: charging, chargeMinutesLeft: nil, tiresPsi: tires, odometerMiles: nil,
            latitude: nil, longitude: nil, supported: [], updatedAt: at ?? now, ignitionOn: ignition)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "RefresherTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: newAlerts

    @Test func risingEdgeOnly() {
        #expect(newAlerts(active: [.lowTire], previouslyActive: []) == [.lowTire])
        #expect(newAlerts(active: [.lowTire], previouslyActive: [.lowTire]) == [])
        #expect(newAlerts(active: [.lowTire, .lowRange], previouslyActive: [.lowTire]) == [.lowRange])
        #expect(newAlerts(active: [], previouslyActive: [.lowTire]) == [])
    }

    @Test func clearedThenRaisedNotifiesAgain() {
        var previous: Set<Alert> = []
        var notified: [Set<Alert>] = []
        for active: Set<Alert> in [[.lowRange], [.lowRange], [], [.lowRange]] {
            notified.append(newAlerts(active: active, previouslyActive: previous))
            previous = active
        }
        #expect(notified == [[.lowRange], [], [], [.lowRange]])
    }

    @Test func disabledNeverNotifies() {
        #expect(newAlerts(active: [.lowTire, .lowRange], previouslyActive: [], enabled: [.lowRange]) == [.lowRange])
        #expect(newAlerts(active: [.leftUnlocked], previouslyActive: [], enabled: []) == [])
    }

    // MARK: unlockedSince

    @Test func unlockedSinceTracksFirstUnlockedRefresh() {
        let t0 = now, t1 = now.addingTimeInterval(300)
        #expect(nextUnlockedSince(nil, locked: false, now: t0) == t0)
        #expect(nextUnlockedSince(t0, locked: false, now: t1) == t0)  // keeps the first time
        #expect(nextUnlockedSince(t0, locked: true, now: t1) == nil)
        #expect(nextUnlockedSince(nil, locked: true, now: t1) == nil)
        #expect(nextUnlockedSince(t0, locked: nil, now: t1) == t0)    // unknown: keep
        #expect(nextUnlockedSince(nil, locked: nil, now: t1) == nil)
    }

    @Test func unlockedSinceOnlyWhileParked() {
        let t0 = now, t1 = now.addingTimeInterval(300)
        // ignition on: driving, not parked; starts nothing and drops what was there
        #expect(nextUnlockedSince(nil, locked: false, ignitionOn: true, now: t0) == nil)
        #expect(nextUnlockedSince(t0, locked: false, ignitionOn: true, now: t1) == nil)
        #expect(nextUnlockedSince(t0, locked: nil, ignitionOn: true, now: t1) == nil)
        // ignition off, or unknown, counts as parked
        #expect(nextUnlockedSince(nil, locked: false, ignitionOn: false, now: t0) == t0)
        #expect(nextUnlockedSince(t0, locked: false, ignitionOn: false, now: t1) == t0)
        #expect(nextUnlockedSince(t0, locked: false, ignitionOn: nil, now: t1) == t0)
    }

    @Test func drivingUnlockedNeverNotifies() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        let driving = snap(locked: false, ignition: true)
        #expect(tracker.update(previous: nil, current: driving, now: now) == [])
        #expect(tracker.update(previous: driving, current: driving, now: now.addingTimeInterval(1200)) == [])
        #expect(d.object(forKey: "unlocked.since") == nil)
        // parked unlocked: the 10 minutes start at the first parked reading
        let parked = snap(locked: false, ignition: false)
        let stop = now.addingTimeInterval(1800)
        #expect(tracker.update(previous: driving, current: parked, now: stop) == [])
        #expect(d.object(forKey: "unlocked.since") as? Date == stop)
        #expect(tracker.update(previous: parked, current: parked, now: stop.addingTimeInterval(599)) == [])
        #expect(tracker.update(previous: parked, current: parked, now: stop.addingTimeInterval(600)) == [.leftUnlocked])
    }

    // MARK: Copy

    @Test func notificationCopy() {
        #expect(alertText(.leftUnlocked, snapshot: snap()) == "Your Jeep is unlocked")
        #expect(alertText(.lowTire, snapshot: snap(tires: ["FL": 35, "FR": 30, "RL": 28, "RR": 35]))
            == "Low tire pressure: rear left 28 psi")
        #expect(alertText(.lowTire, snapshot: snap(tires: ["FR": 29, "RR": 29]))
            == "Low tire pressure: front right 29 psi")  // ties: FL, FR, RL, RR order
        #expect(alertText(.lowRange, snapshot: snap(range: 37)) == "Low range: 37 mi left")
        #expect(alertText(.chargingDone, snapshot: snap()) == "Charging done")
    }

    // MARK: Settings

    @Test func togglesDefaultOnAndPersist() {
        let d = freshDefaults()
        #expect(AlertSettings.key(.lowTire) == "alerts.lowTire")
        #expect(AlertSettings.enabled(in: d) == Set(Alert.allCases))
        d.set(false, forKey: "alerts.lowRange")
        #expect(AlertSettings.isOn(.lowRange, in: d) == false)
        #expect(AlertSettings.enabled(in: d) == [.leftUnlocked, .lowTire, .chargingDone])
    }

    // MARK: Tracker (persisted state across refreshes)

    @Test func trackerNotifiesOncePerCondition() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        let low = snap(range: 30)
        #expect(tracker.update(previous: nil, current: low, now: now) == [.lowRange])
        #expect(d.stringArray(forKey: "alerts.active") == ["lowRange"])
        #expect(tracker.update(previous: low, current: low, now: now.addingTimeInterval(900)) == [])
        let ok = snap(range: 120)
        #expect(tracker.update(previous: low, current: ok, now: now.addingTimeInterval(1800)) == [])
        #expect(d.stringArray(forKey: "alerts.active") == [])
        #expect(tracker.update(previous: ok, current: low, now: now.addingTimeInterval(2700)) == [.lowRange])
    }

    @Test func trackerLeftUnlockedAfterTenMinutes() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        let open = snap(locked: false)
        #expect(tracker.update(previous: nil, current: open, now: now) == [])
        #expect(d.object(forKey: "unlocked.since") as? Date == now)
        #expect(tracker.update(previous: open, current: open, now: now.addingTimeInterval(599)) == [])
        #expect(tracker.update(previous: open, current: open, now: now.addingTimeInterval(600)) == [.leftUnlocked])
        #expect(tracker.update(previous: open, current: open, now: now.addingTimeInterval(1500)) == [])
        // locked: cleared, and the next unlock starts a new 10 minutes
        #expect(tracker.update(previous: open, current: snap(locked: true), now: now.addingTimeInterval(1600)) == [])
        #expect(d.object(forKey: "unlocked.since") == nil)
        let later = now.addingTimeInterval(2000)
        #expect(tracker.update(previous: nil, current: open, now: later) == [])
        #expect(tracker.update(previous: open, current: open, now: later.addingTimeInterval(600)) == [.leftUnlocked])
    }

    @Test func trackerSkipsDisabledAlerts() {
        let d = freshDefaults()
        d.set(false, forKey: "alerts.lowTire")
        let tracker = AlertTracker(defaults: d)
        let s = snap(tires: ["FL": 20], range: 10)
        #expect(tracker.update(previous: nil, current: s, now: now) == [.lowRange])
        #expect(tracker.update(previous: s, current: s, now: now) == [])
    }

    @Test func trackerChargingDoneIsAnEdge() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        let charging = snap(pluggedIn: true, charging: true)
        let done = snap(pluggedIn: true, charging: false)
        #expect(tracker.update(previous: charging, current: done, now: now) == [.chargingDone])
        #expect(tracker.update(previous: done, current: done, now: now) == [])
        #expect(tracker.update(previous: done, current: charging, now: now) == [])
        #expect(tracker.update(previous: charging, current: done, now: now) == [.chargingDone])
    }

    // MARK: Foreground refreshes (observe: learn, never add)

    @Test func foregroundLockClearsLeftUnlocked() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        let open = snap(locked: false), shut = snap(locked: true)
        #expect(tracker.update(previous: nil, current: open, now: now) == [])                                 // BG
        #expect(tracker.update(previous: open, current: open, now: now.addingTimeInterval(600)) == [.leftUnlocked])  // BG
        tracker.observe(previous: open, current: shut, now: now.addingTimeInterval(700))                      // FG locked
        #expect(d.object(forKey: "unlocked.since") == nil)
        #expect(d.stringArray(forKey: "alerts.active") == [])
        tracker.observe(previous: shut, current: open, now: now.addingTimeInterval(800))                      // FG unlocked
        #expect(d.object(forKey: "unlocked.since") as? Date == now.addingTimeInterval(800))
        #expect(tracker.update(previous: open, current: open, now: now.addingTimeInterval(1400)) == [.leftUnlocked])  // BG
    }

    @Test func firstUnlockedTimeComesFromForeground() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        let open = snap(locked: false)
        tracker.observe(previous: nil, current: open, now: now)                                               // FG
        #expect(tracker.update(previous: open, current: open, now: now.addingTimeInterval(600)) == [.leftUnlocked])  // first BG run
    }

    @Test func foregroundNeverAddsSoBackgroundStillNotifies() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        let low = snap(range: 30)
        tracker.observe(previous: nil, current: low, now: now)
        #expect(d.stringArray(forKey: "alerts.active") ?? [] == [])
        tracker.observe(previous: low, current: low, now: now.addingTimeInterval(120))
        #expect(tracker.update(previous: low, current: low, now: now.addingTimeInterval(900)) == [.lowRange])
        // already notified: foreground keeps it active while it stays true, so no repeat
        tracker.observe(previous: low, current: low, now: now.addingTimeInterval(1000))
        #expect(d.stringArray(forKey: "alerts.active") == ["lowRange"])
        #expect(tracker.update(previous: low, current: low, now: now.addingTimeInterval(1800)) == [])
    }

    @Test func trackerResetForgetsState() {
        let d = freshDefaults()
        let tracker = AlertTracker(defaults: d)
        _ = tracker.update(previous: nil, current: snap(locked: false, range: 10), now: now)
        tracker.reset()
        #expect(d.object(forKey: "alerts.active") == nil)
        #expect(d.object(forKey: "unlocked.since") == nil)
    }

    // MARK: Background run guard

    @Test func evaluatesOnlyNewSnapshots() {
        let old = snap(at: now)
        let new = snap(at: now.addingTimeInterval(60))
        #expect(isNewSnapshot(previous: nil, current: new))
        #expect(isNewSnapshot(previous: old, current: new))
        #expect(!isNewSnapshot(previous: old, current: old))
    }
}

struct SignInFormTests {
    @Test func validation() {
        #expect(signInIsValid(email: "me@example.com", password: "pw", pin: "1234"))
        #expect(signInIsValid(email: "  me@example.com ", password: "pw", pin: "0000"))
        #expect(!signInIsValid(email: "", password: "pw", pin: "1234"))
        #expect(!signInIsValid(email: "me", password: "pw", pin: "1234"))
        #expect(!signInIsValid(email: "me@example.com", password: "", pin: "1234"))
        #expect(!signInIsValid(email: "me@example.com", password: "pw", pin: "123"))
        #expect(!signInIsValid(email: "me@example.com", password: "pw", pin: "12345"))
        #expect(!signInIsValid(email: "me@example.com", password: "pw", pin: "12a4"))
        #expect(!signInIsValid(email: "me@example.com", password: "pw", pin: "١٢٣٤"))  // non-ASCII digits
    }

    @Test func pinInputKeepsFourAsciiDigits() {
        #expect(pinInput("12a34") == "1234")
        #expect(pinInput("123456") == "1234")
        #expect(pinInput("٣12") == "12")
        #expect(pinInput("") == "")
    }

    @Test func errorCopy() {
        #expect(signInMessage(for: .badLogin) == "Email or password is wrong.")
        #expect(signInMessage(for: .loginRejected(403120)) == "Uconnect turned down the sign-in. Try again later.")
        #expect(signInMessage(for: .badPin) == "PIN is wrong.")
        #expect(signInMessage(for: .network) == "No connection. Try again.")
        #expect(signInMessage(for: .timeout) == "No connection. Try again.")
        #expect(signInMessage(for: .unexpected("x")) == "Couldn't sign in. Try again.")
    }
}

struct SettingsLabelTests {
    @Test func alertLabels() {
        #expect(Alert.allCases.map(SettingsView.label)
            == ["Left unlocked", "Low tire pressure", "Low range", "Charging done"])
    }
}

struct RootSheetTests {
    @Test func signInWinsOverSettings() {
        #expect(rootSheet(needsSignIn: true, settingsOpen: true) == .signIn)
        #expect(rootSheet(needsSignIn: true, settingsOpen: false) == .signIn)
        #expect(rootSheet(needsSignIn: false, settingsOpen: true) == .settings)
        #expect(rootSheet(needsSignIn: false, settingsOpen: false) == nil)
    }
}
