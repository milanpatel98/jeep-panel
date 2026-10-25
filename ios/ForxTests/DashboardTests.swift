import CoreGraphics
import CoreLocation
import Foundation
import SwiftUI
import Testing
@testable import Forx

struct DashboardLayoutTests {
    @Test func panelTakesThirtyFivePercent() {
        let l = DashboardLayout(size: CGSize(width: 960, height: 360))
        #expect(l.panelWidth == 336)
        #expect(l.card == CGRect(x: 336, y: 12, width: 612, height: 336))
        #expect(l.showsBattery)
        #expect(l.padLeft == 20)
    }

    @Test func designSizeHeader() {
        let l = DashboardLayout(size: CGSize(width: 960, height: 360))
        #expect(l.nameFont == 13)
        #expect(l.heroFont == 30)
        #expect(l.unitFont == 15)
        #expect(l.batteryFont == 13)
        #expect(l.headerTop == 16)
        #expect(abs(l.headerBottom - (16 + 16 + 2 + 35)) < 0.001)
    }

    @Test func jeepFillsFromHeaderToStatus() {
        let l = DashboardLayout(size: CGSize(width: 960, height: 360))
        #expect(l.jeep.minY == l.headerBottom + 2)
        #expect(l.jeep.maxY == l.statusY - l.statusLineHeight / 2 - 2)
        #expect(l.jeep.minX == -10)
        #expect(l.jeep.maxX == l.panelWidth)  // the roof strip sits at the panel's right edge
        #expect(abs(l.statusY + l.statusLineHeight / 2 - (360 - 16)) < 0.0001)
    }

    @Test func typeShrinksToAFloorOnShortWindows() {
        let small = DashboardLayout(size: CGSize(width: 640, height: 240))
        #expect(small.nameFont == 11)
        #expect(small.heroFont == 24)
        #expect(small.unitFont == 12)
        #expect(small.statusFont == 11)
        let big = DashboardLayout(size: CGSize(width: 1920, height: 720))
        #expect(big.heroFont == 30)
        #expect(big.nameFont == 13)
    }

    @Test func narrowPanelDropsTheBattery() {
        #expect(!DashboardLayout(size: CGSize(width: 400, height: 240)).showsBattery)
        #expect(DashboardLayout(size: CGSize(width: 640, height: 240)).showsBattery)
    }

    @Test func partsStayInOrderTopToBottom() {
        for size in [CGSize(width: 640, height: 240), CGSize(width: 400, height: 240), CGSize(width: 960, height: 360), CGSize(width: 800, height: 480)] {
            let l = DashboardLayout(size: size)
            #expect(l.headerBottom < l.jeep.minY)
            #expect(l.jeep.maxY < l.statusY - l.statusLineHeight / 2)
            #expect(l.statusY + l.statusLineHeight / 2 < size.height)
        }
    }

    @Test func globeOverflowsBottomRightAndKeepsTheLabelInside() {
        let l = DashboardLayout(size: CGSize(width: 640, height: 240))  // card 404 × 216
        #expect(l.globeDiameter == 324)
        let m = l.mapFrame
        #expect(abs(m.minX) < 0.0001 && abs(m.minY) < 0.0001)
        #expect(m.maxX >= l.card.width && m.maxY >= l.card.height)
        #expect(abs(l.mapMargins.bottom - (m.maxY - 216)) < 0.0001)
        #expect(abs(l.mapMargins.trailing - (m.maxX - 404)) < 0.0001)
        #expect(l.mapMargins.top == 0 && l.mapMargins.leading == 0)
        #expect(l.dotSize == 8)
        #expect(DashboardLayout(size: CGSize(width: 1520, height: 628)).dotSize == 10)
    }

    @Test func themeColours() {
        #expect(DashboardTheme(dark: true).background == .black)
        #expect(DashboardTheme(dark: false).background == Color(hex: 0xF5F5F7))
        #expect(DashboardTheme(dark: false).card == .white)
        #expect(DashboardTheme(dark: false).text == Color(hex: 0x1C1C1E))
        #expect(DashboardTheme(dark: false).secondary == Color(hex: 0x6E6E73))
    }

    @Test func batteryStepsAndColour() {
        #expect(BatterySymbol.name(62) == "battery.50percent")
        #expect(BatterySymbol.name(88) == "battery.100percent")
        #expect(BatterySymbol.name(12) == "battery.0percent")
        #expect(BatterySymbol.name(nil) == "battery.0percent")
        #expect(BatterySymbol.low(20))
        #expect(!BatterySymbol.low(21))
        #expect(!BatterySymbol.low(nil))
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
