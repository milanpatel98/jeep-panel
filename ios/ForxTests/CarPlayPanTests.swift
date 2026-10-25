import CoreGraphics
import Foundation
import Testing
@testable import Forx

struct CarPlayPanTests {
    @Test func axisLocksAfterTenPointsThenTracksOneToOne() {
        var pan = CarPlayPan()
        #expect(pan.update(CGPoint(x: 6, y: 2)) == nil)  // under 10 pt: undecided
        #expect(pan.axis == nil)
        #expect(pan.update(CGPoint(x: 12, y: 2)) == nil)  // locks, no jump
        #expect(pan.axis == .horizontal)
        #expect(pan.update(CGPoint(x: 22, y: 30)) == .spin(10 * CarPlayPan.degreesPerPoint))
        // stays horizontal even when the finger then drifts mostly down
        #expect(pan.update(CGPoint(x: 17, y: 90)) == .spin(-5 * CarPlayPan.degreesPerPoint))
        #expect(pan.end(velocity: .zero) == .release)
    }

    @Test func verticalDragDoesNothing() {
        var pan = CarPlayPan()
        #expect(pan.update(CGPoint(x: 1, y: 12)) == nil)
        #expect(pan.axis == .vertical)
        #expect(pan.update(CGPoint(x: 1, y: 52)) == nil)
        #expect(pan.update(CGPoint(x: 30, y: 72)) == nil)
        #expect(pan.end(velocity: CGPoint(x: 0, y: 800)) == nil)
    }

    @Test func aTapDoesNothing() {
        var pan = CarPlayPan()
        #expect(pan.update(CGPoint(x: 3, y: 3)) == nil)
        #expect(pan.end(velocity: .zero) == nil)
    }
}

@MainActor
struct DashboardSpinTests {
    @Test func sidewaysDragsBecomePageCalls() {
        var calls: [String] = []
        let spin = DashboardSpin()
        spin.send = { calls.append($0) }

        spin.began()
        spin.changed(CGPoint(x: 12, y: 0))
        spin.changed(CGPoint(x: 22, y: 0))
        spin.ended(.zero)
        #expect(calls == ["spin(4.0)", "release()"])

        // up and down sends nothing
        calls = []
        spin.began()
        spin.changed(CGPoint(x: 0, y: 10))
        spin.changed(CGPoint(x: 0, y: 130))
        spin.ended(.zero)
        #expect(calls.isEmpty)
    }
}
