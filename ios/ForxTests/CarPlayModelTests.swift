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
        supported: Set<JeepCommand> = Set(JeepCommand.allCases), age: TimeInterval = 0
    ) -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: locked, doorsOpen: doorsOpen, tailgateOpen: tailgate,
            rangeMiles: range, fuelPercent: nil, evPercent: ev, pluggedIn: pluggedIn,
            charging: charging, chargeMinutesLeft: chargeMinutes, tiresPsi: tires,
            odometerMiles: odometer, latitude: nil, longitude: nil, supported: supported,
            updatedAt: now.addingTimeInterval(-age), ignitionOn: ignition, gasRangeMiles: nil)
    }

    private func model(
        _ s: JeepSnapshot?, pending: Set<JeepCommand> = [], climateOn: Bool = false,
        message: String? = nil, signedIn: Bool = true, roof: String = "on",
        mode: JeepMode = .hero, mapOpen: Bool = false
    ) -> CarPlayModel {
        CarPlayModel.make(
            snapshot: s, pending: pending, climateOn: climateOn, message: message,
            signedIn: signedIn, roof: roof, mode: mode, mapOpen: mapOpen, now: now, timeZone: TimeZone(identifier: "UTC")!)
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
        #expect(m.gear == "P")
        #expect(m.rangeText == "186")
        #expect(m.evText == "78%")
        #expect(m.buttons.map(\.kind) == [.jeep, .lock, .earth, .apps])
        #expect(button(m, .lock)?.symbol == "lock.fill")
        #expect(button(m, .lock)?.state == .off)
        #expect(button(m, .earth)?.state == .off)
        #expect(button(m, .jeep)?.state == .off)
        #expect(button(m, .apps)?.symbol == "square.grid.3x3.fill")
        #expect(m.roofKey == "on")
        #expect(m.mode == .hero)
        #expect(!m.mapOpen)
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

    @Test func earthAndJeepButtonsShowTheMotion() {
        let m = model(snap(), mode: .turntable, mapOpen: true)
        #expect(button(m, .earth)?.state == .on)
        #expect(button(m, .jeep)?.state == .on)
        #expect(m.mode == .turntable)
        #expect(m.mapOpen)
        #expect(JeepMode.hero.next == .turntable)
        #expect(JeepMode.turntable.next == .tires)
        #expect(JeepMode.tires.next == .hero)
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

        // Climate lives in More now: pending shows "…", on shows "On"
        #expect(row(model(s, pending: [.climateOn]), "Climate")?.detail == "…")
        #expect(row(model(s, climateOn: false), "Climate")?.detail == "")
        #expect(row(model(s, climateOn: true), "Climate")?.detail == "On")
        #expect(row(model(s, climateOn: true), "Climate")?.action == .climateOff)
        #expect(row(model(s, climateOn: false), "Climate")?.action == .climateOn)
    }

    @Test func unsupportedCommandsHidden() {
        let m = model(snap(supported: [.lock, .unlock]))
        #expect(m.buttons.map(\.kind) == [.jeep, .lock, .earth, .apps])
        #expect(m.more.map(\.title) == ["Tires", "Charging", "Trip"])
        #expect(m.buttons.first { $0.kind == .lock }?.isLocked == true)
        #expect(model(snap(locked: nil)).buttons.first { $0.kind == .lock }?.isLocked == nil)

        let all = model(snap())
        #expect(all.more.map(\.title) == ["Climate", "Lights", "Horn", "Tailgate", "Tires", "Charging", "Trip"])
        #expect(row(all, "Lights")?.action == .lights)
        #expect(row(all, "Horn")?.action == .horn)
        #expect(row(all, "Tailgate")?.action == .gate)

        // No lock support: no Lock button.
        #expect(model(snap(supported: [.climateOn])).buttons.map(\.kind) == [.jeep, .earth, .apps])

        // No snapshot: data rows show "—".
        let none = model(nil)
        #expect(none.buttons.map(\.kind) == [.jeep, .earth, .apps])
        #expect(row(none, "Trip")?.detail == "—")
        #expect(row(none, "Charging")?.detail == "—")
        #expect(row(none, "Tires")?.detail == "FL — · FR — · RL — · RR —")
        #expect(none.tires == ["FL": "—", "FR": "—", "RL": "—", "RR": "—"])
        #expect(none.tiresAgo == "—")
    }

    @Test func statusRowCopy() {
        #expect(model(snap(range: 186, ev: 78)).rangeText == "186")
        #expect(model(snap(range: 186, ev: 78)).evText == "78%")
        #expect(model(snap(ignition: true)).gear == "D")
        #expect(model(snap(ignition: nil)).gear == "P")
        #expect(model(nil).gear == "P")
        // Unknown: "—" for the number only; no battery.
        #expect(model(nil).rangeText == "—")
        #expect(model(nil).evText == nil)
        #expect(model(snap(range: nil, ev: nil)).rangeText == "—")
        #expect(model(snap(range: nil, ev: nil)).evText == nil)
        #expect(CarPlayModel.gearLetters == ["P", "R", "N", "D"])
    }

    @Test func appsOrderAndCap() {
        let m = model(snap())
        #expect(m.apps.count == 8)
        #expect(m.apps.map(\.url.absoluteString) == [
            "youtubemusic://", "spotify://", "music://", "maps://",
            "podcasts://", "comgooglemaps://", "waze://", "tel://",
        ])
        #expect(m.apps.map(\.title) == [
            "YouTube Music", "Spotify", "Apple Music", "Apple Maps",
            "Podcasts", "Google Maps", "Waze", "Phone",
        ])
        #expect(CarPlayModel.favouriteApps.map(\.title) == ["YouTube Music", "Spotify", "Apple Music", "Apple Maps"])
        #expect(m.apps.map(\.icon) == [
            "appicon-youtubemusic", "appicon-spotify", "appicon-applemusic", "appicon-applemaps",
            "appicon-podcasts", "appicon-googlemaps", "appicon-waze", "appicon-phone",
        ])
    }

    @Test func lockSymbolAndState() {
        let open = model(snap(locked: false))
        #expect(button(open, .lock)?.symbol == "lock.open.fill")
        #expect(button(open, .lock)?.state == .on)
        let unknown = model(snap(locked: nil))
        #expect(button(unknown, .lock)?.symbol == "lock.fill")
        #expect(button(unknown, .lock)?.state == .off)
        #expect(button(model(snap()), .earth)?.symbol == "location.fill")
    }

    @Test func roofCyclesOnPanelsOffDoorsOff() {
        #expect(CarPlayModel.nextRoof(after: "on") == "panels")
        #expect(CarPlayModel.nextRoof(after: "panels") == "off")
        #expect(CarPlayModel.nextRoof(after: "off") == "doorsOff")
        #expect(CarPlayModel.nextRoof(after: "doorsOff") == "on")
        #expect(CarPlayModel.nextRoof(after: "bogus") == "panels")
        #expect(CarPlayModel.roofIndex("on") == 0)
        #expect(CarPlayModel.roofIndex("doorsOff") == 3)
        #expect(CarPlayModel.roofIndex("bogus") == 0)
        #expect(model(snap(), roof: "panels").roofKey == "panels")
        #expect(model(snap(), roof: "bogus").roofKey == "on")
        #expect(CarPlayModel.roofTitle("off") == "Top off")
    }

    @Test func chargeCalloutAndChargingRow() {
        // now is 2026-10-24 12:00 UTC; 130 min → 2:10 PM.
        let charging = model(snap(charging: true, pluggedIn: true, chargeMinutes: 130))
        #expect(charging.chargeText == "Charging · full by 2:10 PM")
        #expect(row(charging, "Charging")?.detail == "Charging · full by 2:10 PM")
        #expect(model(snap(charging: true, pluggedIn: true)).chargeText == "Charging")
        #expect(model(snap(pluggedIn: true)).chargeText == "Plugged in")
        #expect(row(model(snap(pluggedIn: true)), "Charging")?.detail == "Plugged in")
        // unplugged or unknown: no call-out
        #expect(model(snap()).chargeText == nil)
        #expect(model(snap(pluggedIn: nil)).chargeText == nil)
        #expect(row(model(snap(pluggedIn: nil)), "Charging")?.detail == "—")
        #expect(model(nil).chargeText == nil)
    }

    @Test func tiresAndTheirAge() {
        let m = model(snap(tires: ["FL": 36, "FR": 36, "RL": 35, "RR": 36], age: 38 * 60))
        #expect(m.tires == ["FL": "36", "FR": "36", "RL": "35", "RR": "36"])
        #expect(m.tiresAgo == "38 minutes ago")
        #expect(model(snap()).tiresAgo == "just now")
        #expect(model(snap(age: 59)).tiresAgo == "just now")
        #expect(model(snap(age: 61)).tiresAgo == "1 minute ago")
        #expect(model(snap(age: 3600)).tiresAgo == "1 hour ago")
        #expect(model(snap(age: 5 * 3600)).tiresAgo == "5 hours ago")
        #expect(model(snap(age: 26 * 3600)).tiresAgo == "yesterday")
        #expect(model(snap(age: 3 * 86400)).tiresAgo == "3 days ago")
        #expect(CarPlayModel.ago(from: now.addingTimeInterval(60), to: now) == "just now")  // the future counts as now
    }

    @Test func messagePassesThrough() {
        #expect(model(snap(), message: "Jeep didn't answer. Try again.").message
            == "Jeep didn't answer. Try again.")
        #expect(model(snap()).message == nil)
    }
}
