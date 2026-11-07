import CarPlay
import CoreGraphics
import Foundation
import Testing
@testable import Forx

struct CarPlayPanTests {
    @Test func axisLocksAfterTenPointsThenTracksOneToOne() {
        var pan = CarPlayPan()
        #expect(pan.update(CGPoint(x: 6, y: 2)).isEmpty)  // under 10 pt: undecided
        #expect(pan.axis == nil)
        #expect(pan.update(CGPoint(x: 12, y: 2)).isEmpty)  // locks, no jump
        #expect(pan.axis == .horizontal)
        #expect(pan.update(CGPoint(x: 22, y: 30)) == [.spin(10 * CarPlayPan.degreesPerPoint)])
        // stays horizontal even when the finger then drifts mostly down
        #expect(pan.update(CGPoint(x: 17, y: 90)) == [.spin(-5 * CarPlayPan.degreesPerPoint)])
        #expect(pan.end(velocity: .zero) == [.release])
    }

    @Test func verticalDragWorksTheHandle() {
        var pan = CarPlayPan()
        #expect(pan.update(CGPoint(x: 1, y: -12)).isEmpty)
        #expect(pan.axis == .vertical)
        // the handle follows the finger from where the axis locked
        #expect(pan.update(CGPoint(x: 1, y: -30)) == [.handle(-18)])
        // 44 pt up: one part off; the handle keeps following
        #expect(pan.update(CGPoint(x: 3, y: -60)) == [.roofStep(1), .handle(-48)])
        #expect(pan.update(CGPoint(x: 3, y: -80)) == [.handle(-68)])
        // a little back down is nothing (a full step of travel from the last notch steps back)
        #expect(pan.update(CGPoint(x: 3, y: -50)) == [.handle(-38)])
        #expect(pan.update(CGPoint(x: 3, y: -10)) == [.roofStep(-1), .handle(2)])
        // a fast move crosses two steps at once
        #expect(pan.update(CGPoint(x: 3, y: -104)) == [.roofStep(1), .roofStep(1), .handle(-92)])
        // letting go: the handle springs home
        #expect(pan.end(velocity: CGPoint(x: 0, y: 800)) == [.handleRelease])
    }

    @Test func dragDownPutsPartsBack() {
        var pan = CarPlayPan()
        _ = pan.update(CGPoint(x: 0, y: 12))
        #expect(pan.update(CGPoint(x: 0, y: 60)) == [.roofStep(-1), .handle(48)])
        #expect(pan.update(CGPoint(x: 0, y: 100)) == [.roofStep(-1), .handle(88)])
        // and back up a step: a part comes off again
        #expect(pan.update(CGPoint(x: 0, y: 56)) == [.roofStep(1), .handle(44)])
    }

    @Test func withTheMapOpenSidewaysMovesTheDivider() {
        var pan = CarPlayPan(mapOpen: true)
        _ = pan.update(CGPoint(x: 12, y: 0))
        #expect(pan.update(CGPoint(x: 40, y: 3)) == [.divider(28)])
        #expect(pan.update(CGPoint(x: 90, y: 3)) == [.divider(78)])
        #expect(pan.end(velocity: CGPoint(x: 700, y: 0)) == [.dividerRelease(78, 700)])
    }

    @Test func aTapDoesNothing() {
        var pan = CarPlayPan()
        #expect(pan.update(CGPoint(x: 3, y: 3)).isEmpty)
        #expect(pan.end(velocity: .zero).isEmpty)
    }
}

@MainActor
struct JeepGesturesTests {
    private func make() -> (JeepGestures, DashboardMotion, Recorder) {
        let motion = DashboardMotion()
        let rec = Recorder()
        let g = JeepGestures(motion: motion, setRoof: { rec.roofs.append($0) })
        g.send = { rec.calls.append($0) }
        g.dividerTravel = 400
        g.regionJSON = { dx in "{\"dx\":\(Int(dx))}" }
        g.closeMap = { rec.closes += 1 }
        return (g, motion, rec)
    }

    @Test func sidewaysDragsBecomePageCalls() {
        let (g, _, rec) = make()
        g.began()
        g.changed(CGPoint(x: 12, y: 0))
        g.changed(CGPoint(x: 22, y: 0))
        g.ended(.zero)
        #expect(rec.calls == ["spin(4.0)", "release()"])
    }

    @Test func verticalDragStepsTheRoofAndMovesTheHandle() {
        let (g, _, rec) = make()
        g.roof = "on"
        g.began()
        g.changed(CGPoint(x: 0, y: -12))
        g.changed(CGPoint(x: 0, y: -30))
        #expect(rec.calls == ["handle(-18.0)"])
        g.changed(CGPoint(x: 0, y: -60))
        #expect(rec.roofs == ["panels"])
        #expect(rec.calls.last == "handle(-48.0)")
        // the templates would set `roof` from the model; a test does it by hand
        g.roof = "panels"
        g.changed(CGPoint(x: 0, y: -104))
        #expect(rec.roofs == ["panels", "off"])
        g.ended(.zero)
        #expect(rec.calls.last == "handleRelease()")  // the handle springs home; the Jeep keeps "off"
    }

    @Test func roofNeverStepsPastTheEnds() {
        let (g, _, rec) = make()
        g.roof = "doorsOff"
        g.began()
        g.changed(CGPoint(x: 0, y: -12))
        g.changed(CGPoint(x: 0, y: -100))
        #expect(rec.roofs.isEmpty)  // already at the top
        g.roof = "on"
        g.began()
        g.changed(CGPoint(x: 0, y: 12))
        g.changed(CGPoint(x: 0, y: 100))
        #expect(rec.roofs.isEmpty)  // already at the bottom
    }

    @Test func dividerDragClosesTheMapWhenFarEnough() {
        let (g, motion, rec) = make()
        motion.mapOpen = true
        g.began()
        g.changed(CGPoint(x: 12, y: 0))
        g.changed(CGPoint(x: 62, y: 0))
        #expect(motion.dividerDx == 50)
        #expect(rec.calls.last == "layout({\"dx\":50})")
        g.ended(.zero)  // 50 of 400: not far enough, it glides back
        #expect(motion.dividerDx == 0)
        #expect(rec.closes == 0)
        #expect(rec.calls.last == "layoutRelease()")

        g.began()
        g.changed(CGPoint(x: 12, y: 0))
        g.changed(CGPoint(x: 160, y: 0))
        g.ended(.zero)  // 148 of 400: closes
        #expect(rec.closes == 1)
        #expect(motion.dividerDx == 0)

        // a flick closes it too
        g.began()
        g.changed(CGPoint(x: 12, y: 0))
        g.changed(CGPoint(x: 30, y: 0))
        g.ended(CGPoint(x: 900, y: 0))
        #expect(rec.closes == 2)
        // it never goes left of where it rests
        g.began()
        g.changed(CGPoint(x: -12, y: 0))
        g.changed(CGPoint(x: -60, y: 0))
        #expect(motion.dividerDx == 0)
    }

    @Test func pinchAndTwist() {
        let (g, _, rec) = make()
        g.zoomBegan()
        g.zoom(scale: 1.5)
        #expect(rec.calls == ["zoom(1.5)"])
        g.zoom(scale: 3)  // capped
        #expect(rec.calls.last == "zoom(1.8)")
        g.zoomEnded()
        #expect(rec.calls.last == "zoomEnd()")
        g.rotationBegan()
        g.rotate(.pi / 2)
        #expect(rec.calls.last == "spin(90.0)")
        g.rotate(.pi / 4)
        #expect(rec.calls.last == "spin(-45.0)")
        g.rotationEnded()
        #expect(rec.calls.last == "release()")
    }

    @Test func settleLetsGo() {
        let (g, _, rec) = make()
        g.settle()
        #expect(rec.calls == ["release()", "handleRelease()"])
    }
}
