import CoreGraphics
import Foundation
import Testing
@testable import Forx

struct DashboardLayoutTests {
    @Test func widescreenSplitsTwentyFiveSeventyFive() {
        let l = DashboardLayout(size: CGSize(width: 640, height: 240))  // 1920×720 @3x
        #expect(l.panelWidth == 160)
        #expect(l.card == CGRect(x: 160, y: 12, width: 468, height: 216))
        #expect(abs(l.u - 240.0 / 628) < 0.0001)  // height is the tighter side
    }

    @Test func smallScreenScalesByPanelWidth() {
        let l = DashboardLayout(size: CGSize(width: 400, height: 240))  // 800×480 @2x
        #expect(l.panelWidth == 100)
        #expect(abs(l.u - 100.0 / 380) < 0.0001)
        #expect(l.tile <= l.tileColumn)  // four tiles always fit
    }

    @Test func mockupSizeIsOneToOne() {
        let l = DashboardLayout(size: CGSize(width: 1520, height: 628))
        #expect(l.panelWidth == 380)
        #expect(l.u == 1)
        #expect(l.tile == 60)
        #expect(l.nameFont == 19)
        #expect(l.tilesTop + l.tile + l.tileGap + l.labelFont * 1.25 + l.tileBottom == 628)
    }

    @Test func partsStayInOrderTopToBottom() {
        for size in [CGSize(width: 640, height: 240), CGSize(width: 400, height: 240), CGSize(width: 800, height: 480)] {
            let l = DashboardLayout(size: size)
            #expect(l.headerBottom < l.jeep.minY)
            #expect(l.statusY < l.tilesTop)
            #expect(l.jeep.maxY <= l.tilesTop)
        }
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
