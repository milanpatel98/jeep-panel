import CoreGraphics
import CoreLocation
import Foundation
import Testing
@testable import Forx

struct DashboardLayoutTests {
    @Test func widescreenSplitsTwentyFiveSeventyFive() {
        let l = DashboardLayout(size: CGSize(width: 640, height: 240))  // 1920×720 @3x
        #expect(l.panelWidth == 160)
        #expect(l.card == CGRect(x: 160, y: 12, width: 468, height: 216))
        #expect(abs(l.u - 240.0 / 628) < 0.0001)  // height is the tighter side
        #expect(l.shortSubtitle)
        #expect(l.showsBattery)
    }

    @Test func smallScreenScalesByPanelWidth() {
        let l = DashboardLayout(size: CGSize(width: 400, height: 240))  // 800×480 @2x
        #expect(l.panelWidth == 100)
        #expect(abs(l.u - 100.0 / 380) < 0.0001)
        #expect(l.shortSubtitle)
        #expect(!l.showsBattery)
    }

    @Test func typeStaysBetweenFloorAndMockup() {
        let small = DashboardLayout(size: CGSize(width: 400, height: 240))
        #expect(small.nameFont == 15)
        #expect(small.subFont == 11)
        #expect(small.statusFont == 11)
        let big = DashboardLayout(size: CGSize(width: 3040, height: 1256))  // twice the mockup
        #expect(big.nameFont == 19)
        #expect(big.subFont == 13.5)
        #expect(big.statusFont == 13)
    }

    @Test func mockupSizeIsOneToOne() {
        let l = DashboardLayout(size: CGSize(width: 1520, height: 628))
        #expect(l.panelWidth == 380)
        #expect(l.u == 1)
        #expect(l.avatar == 40)
        #expect(l.nameFont == 19)
        #expect(l.headerBottom == 60)
        #expect(l.jeep.minY == 70)  // the mockup's car top
        #expect(l.jeep.minX == -14)
        #expect(l.jeep.width == 408)
        #expect(abs(l.statusY + l.statusLineHeight / 2 - (628 - 22)) < 0.0001)
        #expect(!l.shortSubtitle)
        #expect(l.subtitle("62% · 186 mi · Parked") == "62% · 186 mi · Parked")
    }

    @Test func partsStayInOrderTopToBottom() {
        for size in [CGSize(width: 640, height: 240), CGSize(width: 400, height: 240), CGSize(width: 800, height: 480)] {
            let l = DashboardLayout(size: size)
            #expect(l.headerBottom < l.jeep.minY)
            #expect(l.jeep.maxY < l.statusY - l.statusLineHeight / 2)
            #expect(l.statusY + l.statusLineHeight / 2 < size.height)
        }
    }

    @Test func narrowPanelDropsParked() {
        let l = DashboardLayout(size: CGSize(width: 640, height: 240))
        #expect(l.subtitle("62% · 186 mi · Parked") == "62% · 186 mi")
        #expect(l.subtitle("— · — mi · Driving") == "— · — mi")
    }

    @Test func globeOverflowsBottomRightAndKeepsTheLabelInside() {
        let l = DashboardLayout(size: CGSize(width: 640, height: 240))
        #expect(l.globeDiameter == 324)
        let m = l.mapFrame
        #expect(abs(m.minX) < 0.0001 && abs(m.minY) < 0.0001)
        #expect(m.maxX >= l.card.width && m.maxY >= l.card.height)
        #expect(abs(l.mapMargins.bottom - (m.maxY - 216)) < 0.0001)
        #expect(abs(l.mapMargins.trailing - (m.maxX - 468)) < 0.0001)
        #expect(l.mapMargins.top == 0 && l.mapMargins.leading == 0)
        #expect(l.dotSize == 8)
        #expect(DashboardLayout(size: CGSize(width: 1520, height: 628)).dotSize == 10)
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
            == #"{"doors":{"BL":false,"BR":true,"FL":true,"FR":false},"gate":true,"lights":false,"locked":true,"reducedMotion":true,"roof":"panels"}"#)
    }

    @Test func unknownJeepLeavesLockedOut() {
        let state = JeepEmbedState.make(snapshot: nil, roof: "on", reducedMotion: false)
        #expect(state["locked"] == nil)
        #expect(JeepEmbedState.json(state)
            == #"{"doors":{"BL":false,"BR":false,"FL":false,"FR":false},"gate":false,"lights":false,"reducedMotion":false,"roof":"on"}"#)
    }
}
