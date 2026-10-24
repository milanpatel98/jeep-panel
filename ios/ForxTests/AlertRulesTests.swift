import Foundation
import Testing
@testable import Forx

struct AlertRulesTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    /// A snapshot that raises nothing on its own.
    private func snap(
        locked: Bool? = true, tires: [String: Int] = ["FL": 35, "FR": 35, "RL": 35, "RR": 35],
        range: Int? = 186, pluggedIn: Bool? = false, charging: Bool? = false
    ) -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: locked, doorsOpen: [], tailgateOpen: nil,
            rangeMiles: range, fuelPercent: nil, evPercent: nil, pluggedIn: pluggedIn,
            charging: charging, chargeMinutesLeft: nil, tiresPsi: tires, odometerMiles: nil,
            latitude: nil, longitude: nil, supported: [], updatedAt: now)
    }

    @Test func leftUnlocked() {
        let unlocked = snap(locked: false)
        #expect(alerts(previous: nil, current: unlocked, unlockedSince: now.addingTimeInterval(-599), now: now) == [])
        #expect(alerts(previous: nil, current: unlocked, unlockedSince: now.addingTimeInterval(-600), now: now) == [.leftUnlocked])
        #expect(alerts(previous: nil, current: unlocked, unlockedSince: nil, now: now) == [])
        #expect(alerts(previous: nil, current: snap(locked: true), unlockedSince: now.addingTimeInterval(-3600), now: now) == [])
    }

    @Test func leftUnlockedOnlyWhenParked() {
        var driving = snap(locked: false)
        driving.ignitionOn = true
        #expect(alerts(previous: nil, current: driving, unlockedSince: now.addingTimeInterval(-3600), now: now) == [])
        var parked = snap(locked: false)
        parked.ignitionOn = false
        #expect(alerts(previous: nil, current: parked, unlockedSince: now.addingTimeInterval(-600), now: now) == [.leftUnlocked])
    }

    @Test func lowTire() {
        #expect(alerts(previous: nil, current: snap(tires: ["FL": 32, "RR": 40]), unlockedSince: nil, now: now) == [])
        #expect(alerts(previous: nil, current: snap(tires: ["FL": 35, "RR": 31]), unlockedSince: nil, now: now) == [.lowTire])
        #expect(alerts(previous: nil, current: snap(tires: [:]), unlockedSince: nil, now: now) == [])
    }

    @Test func lowRange() {
        #expect(alerts(previous: nil, current: snap(range: 40), unlockedSince: nil, now: now) == [])
        #expect(alerts(previous: nil, current: snap(range: 39), unlockedSince: nil, now: now) == [.lowRange])
        #expect(alerts(previous: nil, current: snap(range: nil), unlockedSince: nil, now: now) == [])
    }

    @Test func chargingDone() {
        let charging = snap(pluggedIn: true, charging: true)
        let done = snap(pluggedIn: true, charging: false)
        #expect(alerts(previous: charging, current: done, unlockedSince: nil, now: now) == [.chargingDone])
        #expect(alerts(previous: done, current: done, unlockedSince: nil, now: now) == [])
        #expect(alerts(previous: nil, current: done, unlockedSince: nil, now: now) == [])
        // unplugged mid-charge is not "done"
        #expect(alerts(previous: charging, current: snap(pluggedIn: false, charging: false), unlockedSince: nil, now: now) == [])
    }

    @Test func severalAtOnceInCaseOrder() {
        let s = snap(locked: false, tires: ["FL": 20], range: 10)
        #expect(alerts(previous: nil, current: s, unlockedSince: now.addingTimeInterval(-900), now: now)
            == [.leftUnlocked, .lowTire, .lowRange])
    }
}
