import CoreGraphics
import CoreLocation
import Foundation
import SwiftUI
import Testing
@testable import Forx

/// Layout numbers are CGFloat: compare them with a tolerance, never ==.
private func near(_ a: CGFloat, _ b: CGFloat) -> Bool {
    abs(a - b) < 0.001
}

struct DashboardLayoutTests {
    private let l = DashboardLayout(size: CGSize(width: 910, height: 360))

    @Test func carRegionKeepsClearOfTheStatusRowAndTheButtons() {
        let r = l.region(mapOpen: false)
        #expect(near(r.minX, 0) && near(r.minY, 40))
        #expect(near(r.maxX, 910 - 70) && near(r.maxY, 354))
        #expect(DashboardLayout.regionJSON(r) == "{\"x0\":0,\"y0\":40,\"x1\":840,\"y1\":354}")
    }

    @Test func mapOpenSplitsTheScreen() {
        #expect(near(l.splitX, 419))  // 46%
        let r = l.region(mapOpen: true)
        #expect(near(r.maxX, 419 - 10))
        let m = l.mapFrame(open: true)
        #expect(near(m.minX, 419) && near(m.maxX, 910) && near(m.height, 360) && near(m.minY, 0))
        // closed: just off the right edge, same width
        let c = l.mapFrame(open: false)
        #expect(near(c.minX, 910) && near(c.width, m.width))
        #expect(near(l.dividerTravel, 910 - 419))
        // a finger pulling the divider right takes the car's region with it
        #expect(near(l.region(mapOpen: true, dividerDx: 100).maxX, 509))
        #expect(near(l.mapFrame(open: true, dividerDx: 100).minX, 519))
        // never past the button column
        #expect(near(l.region(mapOpen: true, dividerDx: 900).maxX, 840))
    }

    @Test func statusRowAndType() {
        #expect(near(l.statusOrigin.x, 20) && near(l.statusOrigin.y, 13))
        #expect(near(l.statusFont, 13))
        #expect(near(DashboardLayout(size: CGSize(width: 640, height: 240)).statusFont, 11))
        #expect(near(DashboardLayout(size: CGSize(width: 1920, height: 720)).statusFont, 13))
    }

    @Test func trayRowsSitOnTheMapButtons() {
        let centres = l.buttonCentres(count: 4)
        #expect(centres.count == 4)
        #expect(near(centres[3], 360 - 22.5))
        #expect(near(centres[2], 360 - 22.5 - 44))
        #expect(near(centres[0], 360 - 22.5 - 3 * 44))
        let tray = l.trayFrame(count: 4)
        #expect(near(tray.maxX, 910) && near(tray.maxY, 360))
        #expect(tray.minY < centres[0] - 22)  // the title fits above the first row
        #expect(l.buttonCentres(count: 0).isEmpty)
    }

    @Test func themeColours() {
        #expect(DashboardTheme(dark: true).background == .black)
        #expect(DashboardTheme(dark: false).background == Color(hex: 0xF5F5F7))
        #expect(DashboardTheme(dark: false).text == Color(hex: 0x1C1C1E))
        #expect(DashboardTheme(dark: false).secondary == Color(hex: 0x6E6E73))
    }

    @Test func batteryFillAndColour() {
        #expect(near(BatteryGauge.fill(78), 0.78))
        #expect(near(BatteryGauge.fill(140), 1))
        #expect(near(BatteryGauge.fill(-5), 0))
        #expect(near(BatteryGauge.fill(nil), 0))
        #expect(BatteryGauge.low(20))
        #expect(!BatteryGauge.low(21))
        #expect(!BatteryGauge.low(nil))
    }

    @Test func boltBreathesBetweenHalfAndFull() {
        #expect(abs(BreathingBolt.opacity(at: 0) - 1) < 0.0001)
        #expect(abs(BreathingBolt.opacity(at: 0.8) - 0.45) < 0.0001)
        #expect(abs(BreathingBolt.opacity(at: 1.6) - 1) < 0.0001)
    }

    @MainActor @Test func demoJeepOnlyWithTheDemoMode() {
        // tests run without FORX_CP: no fixture
        #expect(CarPlayDebug.demo ? CarPlayDebug.demoSnapshot() != nil : CarPlayDebug.demoSnapshot() == nil)
        #expect(!CarPlayDebug.demo || CarPlayDebug.demoOpen == (CarPlayDebug.demoSnapshot()?.tailgateOpen ?? false))
    }
}

struct JeepMapCameraTests {
    @Test func looksAtTheJeepFromAbove() {
        let (c, d) = JeepMapCamera.center(for: CLLocationCoordinate2D(latitude: 39.7, longitude: -105.2))
        #expect(abs(c.latitude - 39.7) < 0.0001 && c.longitude == -105.2)
        #expect(d == JeepMapCamera.distance)
        let (none, far) = JeepMapCamera.center(for: nil)
        #expect(none.longitude == 0 && far > 1_000_000)
        #expect(JeepMapCamera.center(for: kCLLocationCoordinate2DInvalid).1 > 1_000_000)
    }
}

struct JeepEmbedStateTests {
    private func snap(locked: Bool?, doorsOpen: [String], tailgate: Bool?) -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: locked, doorsOpen: doorsOpen, tailgateOpen: tailgate,
            rangeMiles: nil, fuelPercent: nil, evPercent: nil, pluggedIn: nil, charging: nil,
            chargeMinutesLeft: nil, tiresPsi: [:], odometerMiles: nil, latitude: nil, longitude: nil,
            supported: [], updatedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func mapsDoorsGateRoofAndMotion() {
        let state = JeepEmbedState.make(
            snapshot: snap(locked: true, doorsOpen: ["driver", "rightRear"], tailgate: true),
            roof: "panels", reducedMotion: true, mode: .tires, charge: "Plugged in",
            tires: ["FL": "36", "FR": "36", "RL": "35", "RR": "36"], tiresAgo: "38 minutes ago")
        #expect(JeepEmbedState.json(state)
            == #"{"charge":"Plugged in","doors":{"BL":false,"BR":true,"FL":true,"FR":false},"doorsOff":false,"gate":true,"lights":false,"locked":true,"mode":"tires","reducedMotion":true,"roof":"panels","theme":"dark","tires":{"ago":"38 minutes ago","FL":"36","FR":"36","RL":"35","RR":"36"}}"#)
    }

    @Test func unknownJeepSendsNullLock() {
        let state = JeepEmbedState.make(snapshot: nil, roof: "on", reducedMotion: false)
        #expect(state["locked"] is NSNull)
        #expect(state["charge"] is NSNull)
        #expect(JeepEmbedState.json(state)
            == #"{"charge":null,"doors":{"BL":false,"BR":false,"FL":false,"FR":false},"doorsOff":false,"gate":false,"lights":false,"locked":null,"mode":"hero","reducedMotion":false,"roof":"on","theme":"dark","tires":{"ago":""}}"#)
        #expect(JeepEmbedState.make(snapshot: snap(locked: nil, doorsOpen: [], tailgate: nil), roof: "on", reducedMotion: false)["locked"] is NSNull)
        #expect(JeepEmbedState.make(snapshot: snap(locked: false, doorsOpen: [], tailgate: nil), roof: "on", reducedMotion: false)["locked"] as? Bool == false)
    }

    @Test func doorsOffIsTopOffWithoutDoors() {
        let state = JeepEmbedState.make(snapshot: nil, roof: "doorsOff", reducedMotion: false)
        #expect(state["roof"] as? String == "off")
        #expect(state["doorsOff"] as? Bool == true)
    }

    @Test func dayGivesTheLightTheme() {
        let state = JeepEmbedState.make(snapshot: nil, roof: "on", reducedMotion: false, dark: false)
        #expect(state["theme"] as? String == "light")
    }

    @Test func regionJoinsThePageState() {
        let l = DashboardLayout(size: CGSize(width: 910, height: 360))
        let s = DashboardView.pageState(["theme": "dark"], layout: l, mapOpen: true)
        #expect((s["region"] as? [String: Int]) == ["x0": 0, "y0": 40, "x1": 409, "y1": 354])
        #expect(s["theme"] as? String == "dark")
    }

    @Test func pageMessages() {
        #expect(JeepEmbedState.page(["type": "loader"]) == .loading(0))
        #expect(JeepEmbedState.page(["type": "progress", "value": 0.4]) == .loading(0.4))
        #expect(JeepEmbedState.page(["type": "progress", "value": 7.0]) == .loading(1))
        #expect(JeepEmbedState.page(["type": "ready"]) == .ready)
        #expect(JeepEmbedState.page(["type": "error", "message": "x"]) == nil)
        #expect(JeepEmbedState.page("junk") == nil)
    }
}
