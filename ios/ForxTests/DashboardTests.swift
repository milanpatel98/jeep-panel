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
    @Test func twoCardsShareTopAndBottom() {
        let l = DashboardLayout(size: CGSize(width: 960, height: 360))
        // Jeep card: 6 from the leading edge, 35% of the width
        #expect(near(l.jeepCard.minX, 6) && near(l.jeepCard.minY, 6))
        #expect(near(l.jeepCard.width, 336) && near(l.jeepCard.height, 348))
        // globe card: 10 pt after it, to 6 pt from the trailing edge, same top and bottom
        #expect(near(l.card.minX, 352) && near(l.card.minY, 6))
        #expect(near(l.card.maxX, 954))
        #expect(near(l.card.height, l.jeepCard.height) && near(l.card.maxY, 354))
        #expect(near(DashboardLayout.cardRadius, 24))
        #expect(l.showsBattery)
    }

    @Test func designSizeJeepCard() {
        let l = DashboardLayout(size: CGSize(width: 960, height: 360))
        #expect(near(l.nameFont, 12))
        #expect(near(l.nameTop, 18))
        #expect(near(l.heroFont, 34))
        #expect(near(l.unitFont, 15))
        #expect(near(l.energyFont, 13))
        #expect(near(l.heroTop, l.nameTop + l.nameLine))
        // the Jeep: full card width, from y 74 to 38 above the card's bottom
        #expect(near(l.jeep.minX, 0) && near(l.jeep.minY, 74))
        #expect(near(l.jeep.width, 336) && near(l.jeep.maxY, 348 - 38))
        // the status line's bottom 16 above the card's
        #expect(near(l.statusBottom, 348 - 16))
    }

    @Test func typeShrinksToAFloorOnShortWindows() {
        let small = DashboardLayout(size: CGSize(width: 640, height: 240))
        #expect(near(small.nameFont, 11))
        #expect(near(small.heroFont, 26))
        #expect(near(small.unitFont, 12))
        #expect(near(small.energyFont, 11))
        #expect(near(small.statusFont, 11))
        let big = DashboardLayout(size: CGSize(width: 1920, height: 720))
        #expect(near(big.heroFont, 34))
        #expect(near(big.nameFont, 12))
    }

    @Test func narrowCardDropsTheBattery() {
        #expect(!DashboardLayout(size: CGSize(width: 400, height: 240)).showsBattery)
        #expect(DashboardLayout(size: CGSize(width: 640, height: 240)).showsBattery)
    }

    @Test func partsStayInOrderTopToBottom() {
        for size in [CGSize(width: 640, height: 240), CGSize(width: 400, height: 240), CGSize(width: 960, height: 360), CGSize(width: 800, height: 480)] {
            let l = DashboardLayout(size: size)
            #expect(l.nameTop + l.nameLine <= l.heroTop)
            #expect(l.heroTop + l.heroLine <= l.jeep.minY)
            #expect(l.jeep.maxY <= l.statusBottom - l.statusLineHeight)
            #expect(l.statusBottom < l.jeepCard.height)
            #expect(l.jeep.height > 80)
            #expect(near(l.card.minX - l.jeepCard.maxX, 10))
        }
    }

    @Test func globeOverflowsBottomRightAndKeepsTheLabelInside() {
        let l = DashboardLayout(size: CGSize(width: 640, height: 240))  // card 394 × 228
        #expect(near(l.globeDiameter, 342))
        let m = l.mapFrame
        #expect(abs(m.minX) < 0.0001 && abs(m.minY) < 0.0001)
        #expect(m.maxX >= l.card.width && m.maxY >= l.card.height)
        #expect(abs(l.mapMargins.bottom - (m.maxY - 228)) < 0.0001)
        #expect(abs(l.mapMargins.trailing - (m.maxX - 394)) < 0.0001)
        #expect(near(l.mapMargins.top, 0) && near(l.mapMargins.leading, 0))
        #expect(near(l.dotSize, 8))
        #expect(near(DashboardLayout(size: CGSize(width: 1520, height: 628)).dotSize, 10))
    }

    @Test func themeColours() {
        #expect(DashboardTheme(dark: true).background == .black)
        #expect(DashboardTheme(dark: false).background == Color(hex: 0xF5F5F7))
        #expect(DashboardTheme(dark: false).card == .white)
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
        #expect(CarPlayDebug.mode != "demo" ? CarPlayDebug.demoSnapshot() == nil : true)
    }
}

struct GlobeFitTests {
    @Test func distanceGivesTheWantedRadius() throws {
        let r = GlobeFit.earthRadius, f = 500.0, current = 22_000_000.0, a = GlobeFit.probeAngle
        let measured = f * r * sin(a) / (current + r - r * cos(a))
        let d = try #require(GlobeFit.distance(measured: measured, at: current, radius: 300))
        let expected = r * (1 + (f / 300) * (f / 300)).squareRoot() - r
        #expect(abs(d - expected) < 1)
        #expect(GlobeFit.distance(measured: .nan, at: current, radius: 300) == nil)
    }

    @Test func cameraLooksSouthOfTheJeep() {
        let c = GlobeFit.cameraCenter(for: CLLocationCoordinate2D(latitude: 39.7, longitude: -105.2))
        #expect(abs(c.latitude - 24.7) < 0.0001 && c.longitude == -105.2)
        #expect(GlobeFit.cameraCenter(for: nil).latitude == 0)
        #expect(GlobeFit.probe(from: CLLocationCoordinate2D(latitude: 70, longitude: 0)).latitude == 40)
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
            roof: "panels", reducedMotion: true)
        #expect(JeepEmbedState.json(state)
            == #"{"doors":{"BL":false,"BR":true,"FL":true,"FR":false},"doorsOff":false,"gate":true,"lights":false,"locked":true,"reducedMotion":true,"roof":"panels","theme":"dark"}"#)
    }

    @Test func unknownJeepLeavesLockedOut() {
        let state = JeepEmbedState.make(snapshot: nil, roof: "on", reducedMotion: false)
        #expect(state["locked"] == nil)
        #expect(JeepEmbedState.json(state)
            == #"{"doors":{"BL":false,"BR":false,"FL":false,"FR":false},"doorsOff":false,"gate":false,"lights":false,"reducedMotion":false,"roof":"on","theme":"dark"}"#)
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
}
