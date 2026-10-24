import Foundation
import Testing
@testable import Forx

struct CarPlayModelTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    private func snap(
        locked: Bool? = true, range: Int? = 186, ev: Int? = 78, ignition: Bool? = false,
        doorsOpen: [String] = [], tailgate: Bool? = nil, charging: Bool? = false,
        pluggedIn: Bool? = false, chargeMinutes: Int? = nil, odometer: Int? = 7671,
        tires: [String: Int] = ["FL": 35, "FR": 35, "RL": 34],
        supported: Set<JeepCommand> = Set(JeepCommand.allCases)
    ) -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: locked, doorsOpen: doorsOpen, tailgateOpen: tailgate,
            rangeMiles: range, fuelPercent: nil, evPercent: ev, pluggedIn: pluggedIn,
            charging: charging, chargeMinutesLeft: chargeMinutes, tiresPsi: tires,
            odometerMiles: odometer, latitude: nil, longitude: nil, supported: supported,
            updatedAt: now, ignitionOn: ignition, gasRangeMiles: nil)
    }

    private func model(
        _ s: JeepSnapshot?, pending: Set<JeepCommand> = [], climateOn: Bool = false,
        message: String? = nil, signedIn: Bool = true, roof: String = "on"
    ) -> CarPlayModel {
        CarPlayModel.make(
            snapshot: s, pending: pending, climateOn: climateOn, message: message,
            signedIn: signedIn, roof: roof, now: now, timeZone: TimeZone(identifier: "UTC")!)
    }

    private func button(_ m: CarPlayModel, _ kind: CarPlayButtonKind) -> CarPlayButton? {
        m.buttons.first { $0.kind == kind }
    }

    private func row(_ m: CarPlayModel, _ title: String) -> CarPlayRow? {
        m.more.first { $0.title == title }
    }

    @Test func showsCachedSnapshotWhenNoPhoneUI() {
        // Only the cached snapshot is available (the phone app was never opened).
        let m = model(snap())
        #expect(m.signedIn)
        #expect(m.name == "Milan")
        #expect(m.subtitle == "78% · 186 mi · Parked")
        #expect(m.status == "Locked · all doors closed")
        #expect(m.statusKnown)
        #expect(m.buttons.map(\.kind) == [.lock, .climate, .lights, .more])
        #expect(button(m, .lock)?.symbol == "lock.fill")
        #expect(button(m, .lock)?.state == .off)
        #expect(row(m, "Tires")?.detail == "FL 35 · FR 35 · RL 34 · RR —")
        #expect(row(m, "Trip")?.detail == "7,671 mi")
        #expect(row(m, "Charging")?.detail == "Unplugged")
    }

    @Test func notSignedInHidesButtons() {
        let m = model(snap(), signedIn: false)
        #expect(!m.signedIn)
        #expect(m.buttons.isEmpty)
        #expect(model(nil, signedIn: false).buttons.isEmpty)
    }

    @Test func pendingThenFailureRevertsButton() {
        let s = snap(locked: true)
        let sent = model(s, pending: [.unlock])
        #expect(button(sent, .lock)?.state == .pending)
        #expect(button(sent, .lock)?.symbol == "lock.fill")
        // Command failed: nothing pending, the Jeep still reports locked.
        let failed = model(s, pending: [])
        #expect(button(failed, .lock)?.state == .off)
        #expect(button(failed, .lock)?.symbol == "lock.fill")

        let climateSent = model(s, pending: [.climateOn], climateOn: false)
        #expect(button(climateSent, .climate)?.state == .pending)
        #expect(button(model(s, climateOn: false), .climate)?.state == .off)
        #expect(button(model(s, climateOn: true), .climate)?.state == .on)
    }

    @Test func unsupportedCommandsHidden() {
        let m = model(snap(supported: [.lock, .unlock]))
        #expect(m.buttons.map(\.kind) == [.lock, .more])
        let titles = m.more.map(\.title)
        #expect(!titles.contains("Horn"))
        #expect(!titles.contains("Tailgate"))
        #expect(titles == ["Tires", "Charging", "Top on", "Panels off", "Top off", "Trip"])
        #expect(m.more.filter(\.roof).map(\.title) == ["Top on", "Panels off", "Top off"])
        #expect(m.more.compactMap(\.roofKey) == ["on", "panels", "off"])
        #expect(m.more.filter { !$0.roof }.allSatisfy { $0.roofKey == nil })
        #expect(m.buttons.first { $0.kind == .lock }?.isLocked == true)
        #expect(model(snap(locked: nil)).buttons.first { $0.kind == .lock }?.isLocked == nil)

        let all = model(snap())
        #expect(all.more.map(\.title)
            == ["Tires", "Charging", "Top on", "Panels off", "Top off", "Horn", "Tailgate", "Trip"])
        #expect(row(all, "Horn")?.action == .horn)
        #expect(row(all, "Tailgate")?.action == .gate)

        // No snapshot: only More, and data rows show "—".
        let none = model(nil)
        #expect(none.buttons.map(\.kind) == [.more])
        #expect(row(none, "Trip")?.detail == "—")
        #expect(row(none, "Charging")?.detail == "—")
        #expect(row(none, "Tires")?.detail == "FL — · FR — · RL — · RR —")
    }

    @Test func subtitleCopy() {
        #expect(model(snap(range: 186, ev: 78)).subtitle == "78% · 186 mi · Parked")
        #expect(model(snap(ignition: nil)).subtitle == "78% · 186 mi · Parked")
        #expect(model(snap(ignition: true)).subtitle == "78% · 186 mi · Driving")
        #expect(model(nil).subtitle == "— · — mi · Parked")
    }

    @Test func appsOrderAndCap() {
        let m = model(snap())
        #expect(m.apps.count == 8)
        #expect(m.apps.map(\.url.absoluteString) == [
            "youtubemusic://", "spotify://", "music://", "podcasts://",
            "maps://", "comgooglemaps://", "waze://", "tel://",
        ])
        #expect(m.apps.map(\.title) == [
            "YouTube Music", "Spotify", "Apple Music", "Podcasts",
            "Apple Maps", "Google Maps", "Waze", "Phone",
        ])
    }

    @Test func statusCopy() {
        #expect(model(snap(locked: false)).status == "Unlocked")
        #expect(model(snap(doorsOpen: ["driver"])).status == "Driver door open")
        #expect(model(snap(doorsOpen: ["driver", "rightRear"])).status
            == "Driver door, Rear right door open")
        #expect(model(snap(doorsOpen: ["driver", "passenger", "leftRear", "rightRear"])).status
            == "All doors open")
        #expect(model(snap(locked: false, doorsOpen: ["passenger"], tailgate: true)).status
            == "Passenger door open · Tailgate open · Unlocked")
        let unknown = model(snap(locked: nil))
        #expect(unknown.status == "—")
        #expect(!unknown.statusKnown)
        #expect(!model(nil).statusKnown)
    }

    @Test func lockSymbolAndState() {
        let open = model(snap(locked: false))
        #expect(button(open, .lock)?.symbol == "lock.open.fill")
        #expect(button(open, .lock)?.state == .on)
        let unknown = model(snap(locked: nil))
        #expect(button(unknown, .lock)?.symbol == "lock.fill")
        #expect(button(unknown, .lock)?.state == .off)
        #expect(button(model(snap()), .lights)?.state == .off)
        #expect(button(model(snap(), pending: [.lights]), .lights)?.state == .pending)
        #expect(button(model(snap()), .more)?.symbol == "ellipsis")
    }

    @Test func roofCheckAndCharging() {
        let m = model(snap(), roof: "panels")
        #expect(row(m, "Top on")?.detail == "")
        #expect(row(m, "Panels off")?.detail == "✓")
        #expect(row(m, "Top off")?.detail == "")
        #expect(m.more.filter(\.roof).allSatisfy { $0.action == nil })

        // now is 2026-10-24 12:00 UTC; 130 min → 2:10 PM.
        let charging = model(snap(charging: true, pluggedIn: true, chargeMinutes: 130))
        #expect(row(charging, "Charging")?.detail == "Charging · full by 2:10 PM")
        #expect(row(model(snap(charging: true, pluggedIn: true)), "Charging")?.detail == "Charging")
        #expect(row(model(snap(pluggedIn: true)), "Charging")?.detail == "Plugged in")
    }

    @Test func messagePassesThrough() {
        #expect(model(snap(), message: "Jeep didn't answer. Try again.").message
            == "Jeep didn't answer. Try again.")
        #expect(model(snap()).message == nil)
    }
}
