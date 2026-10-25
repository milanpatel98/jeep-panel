import CoreGraphics
import Foundation
import Testing
@testable import Forx

struct CarPlayPanTests {
    @Test func axisLocksAfterTenPointsThenTracksOneToOne() {
        var pan = CarPlayPan(startStep: 0)
        #expect(pan.update(CGPoint(x: 6, y: 2)) == nil)  // under 10 pt: undecided
        #expect(pan.axis == nil)
        #expect(pan.update(CGPoint(x: 12, y: 2)) == nil)  // locks, no jump
        #expect(pan.axis == .horizontal)
        #expect(pan.update(CGPoint(x: 22, y: 30)) == .spin(10 * CarPlayPan.degreesPerPoint))
        // stays horizontal even when the finger then drifts mostly down
        #expect(pan.update(CGPoint(x: 17, y: 90)) == .spin(-5 * CarPlayPan.degreesPerPoint))
        #expect(pan.end(velocity: .zero) == .release)
    }

    @Test func verticalDragStepsTheStrip() {
        var pan = CarPlayPan(startStep: 0)
        #expect(pan.update(CGPoint(x: 1, y: 12)) == nil)
        #expect(pan.axis == .vertical)
        #expect(pan.update(CGPoint(x: 1, y: 52)) == .strip(1))
        #expect(pan.update(CGPoint(x: 3, y: 72)) == .strip(1.5))
        #expect(pan.end(velocity: .zero) == .stripRelease(2))
    }

    @Test func pastTheEndsItResistsAndSnapsBack() {
        var pan = CarPlayPan(startStep: 0)
        _ = pan.update(CGPoint(x: 0, y: -12))
        guard case .strip(let p)? = pan.update(CGPoint(x: 0, y: -412)) else {
            Issue.record("expected a strip position"); return
        }
        #expect(p < 0 && p > -CarPlayPan.overshoot)
        #expect(pan.end(velocity: .zero) == .stripRelease(0))
    }

    @Test func aFlickGoesFurther() {
        var pan = CarPlayPan(startStep: 1)
        _ = pan.update(CGPoint(x: 0, y: 10))
        #expect(pan.update(CGPoint(x: 0, y: 30)) == .strip(1.5))
        #expect(pan.end(velocity: CGPoint(x: 0, y: 800)) == .stripRelease(3))
    }

    @Test func aTapDoesNothing() {
        var pan = CarPlayPan(startStep: 2)
        #expect(pan.update(CGPoint(x: 3, y: 3)) == nil)
        #expect(pan.end(velocity: .zero) == nil)
    }
}

@MainActor
struct DashboardSpinTests {
    @Test func dragsBecomePageCallsAndTheRoof() {
        var calls: [String] = []
        var roofs: [String] = []
        let spin = DashboardSpin(currentStep: { 0 }, setRoof: { roofs.append($0) })
        spin.send = { calls.append($0) }

        spin.began()
        spin.changed(CGPoint(x: 12, y: 0))
        spin.changed(CGPoint(x: 22, y: 0))
        spin.ended(.zero)
        #expect(calls == ["spin(4.0)", "release()"])

        calls = []
        spin.began()
        spin.changed(CGPoint(x: 0, y: 10))
        spin.changed(CGPoint(x: 0, y: 130))
        spin.ended(.zero)
        #expect(calls == ["strip(3.0)", "stripRelease(3)"])
        #expect(roofs == ["doorsOff"])
    }
}
