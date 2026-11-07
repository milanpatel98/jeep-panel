import CarPlay
import Foundation
import Testing
@testable import Forx

@MainActor
final class FakeCarPlayInterface: CarPlayInterface {
    var roots: [CPTemplate] = []
    var pushed: [CPTemplate] = []
    func setRoot(_ t: CPTemplate) { roots.append(t) }
    func push(_ t: CPTemplate) { pushed.append(t) }
    var topTemplate: CPTemplate? { pushed.last ?? roots.last }
}

@MainActor
final class Recorder {
    var urls: [URL] = []
    var commands: [JeepCommand] = []
    var roofs: [String] = []
    var calls: [String] = []
    var closes = 0
    var completions = 0
}

@MainActor
struct CarPlaySceneTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    private func snap(
        locked: Bool? = true, supported: Set<JeepCommand> = Set(JeepCommand.allCases)
    ) -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: locked, doorsOpen: [], tailgateOpen: nil,
            rangeMiles: 186, fuelPercent: nil, evPercent: 78, pluggedIn: false,
            charging: false, chargeMinutesLeft: nil, tiresPsi: ["FL": 35, "FR": 35, "RL": 34, "RR": 35],
            odometerMiles: 7671, latitude: nil, longitude: nil, supported: supported,
            updatedAt: now, ignitionOn: false, gasRangeMiles: nil)
    }

    private func model(
        _ s: JeepSnapshot?, signedIn: Bool = true, pending: Set<JeepCommand> = [], climateOn: Bool = false,
        roof: String = "on", mode: JeepMode = .hero, mapOpen: Bool = false
    ) -> CarPlayModel {
        CarPlayModel.make(
            snapshot: s, pending: pending, climateOn: climateOn, message: nil,
            signedIn: signedIn, roof: roof, mode: mode, mapOpen: mapOpen, now: now, timeZone: TimeZone(identifier: "UTC")!)
    }

    private func make(_ fake: FakeCarPlayInterface, _ rec: Recorder, gestures: JeepGestures? = nil) -> CarPlayTemplates {
        CarPlayTemplates(
            interface: fake,
            open: { rec.urls.append($0) },
            perform: { rec.commands.append($0) },
            setRoof: { rec.roofs.append($0) },
            email: { "milan@example.com" },
            gestures: gestures)
    }

    @Test func mapButtonsMatchModel() {
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        let full = model(snap())
        t.update(full)
        #expect(fake.roots.count == 1)
        #expect(fake.roots.first === t.mapTemplate)
        #expect(t.mapTemplate.mapButtons.count == 4)
        #expect(t.shownButtons.map(\.kind) == [.jeep, .lock, .earth, .apps])
        #expect(t.mapTemplate.leadingNavigationBarButtons.isEmpty)  // nothing over the status row
        #expect(t.mapTemplate.trailingNavigationBarButtons.count == 2)  // Roof, More; Settings is in More
        #expect(t.mapTemplate.automaticallyHidesNavigationBar)
        #expect(t.mapTemplate.hidesButtonsWithNavigationBar)  // all buttons auto-hide

        // The same model again reassigns nothing (no flicker).
        let mapBefore = t.mapTemplate.mapButtons
        let barBefore = t.mapTemplate.trailingNavigationBarButtons
        t.update(full)
        #expect(t.mapTemplate.mapButtons.first === mapBefore.first)
        #expect(t.mapTemplate.trailingNavigationBarButtons.first === barBefore.first)

        // No lock support: Lock is absent; same map template, updated in place.
        let noLock = model(snap(supported: [.climateOn, .lights]))
        t.update(noLock)
        #expect(fake.roots.count == 1)
        #expect(t.mapTemplate.mapButtons.count == 3)
        #expect(t.shownButtons.map(\.kind) == [.jeep, .earth, .apps])

        // The Roof bar button is redrawn for each roof.
        t.update(model(snap(), roof: "panels"))
        #expect(t.mapTemplate.trailingNavigationBarButtons.first !== barBefore.first)

        // Not signed in: no map buttons, only Settings.
        t.update(model(snap(), signedIn: false))
        #expect(t.mapTemplate.mapButtons.isEmpty)
        #expect(t.mapTemplate.leadingNavigationBarButtons.isEmpty)
        #expect(t.mapTemplate.trailingNavigationBarButtons.count == 1)
    }

    @Test func lockTapSendsUnlockWhenLocked() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        t.update(model(snap(locked: true)))
        t.tap(.lock)
        t.update(model(snap(locked: false)))
        t.tap(.lock)
        #expect(rec.commands == [.unlock, .lock])
    }

    @Test func roofBarButtonCyclesTheRoof() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        var roof = "on"
        for _ in 0..<4 {
            t.update(model(snap(), roof: roof))
            t.stepRoof()
            roof = rec.roofs.last ?? roof
        }
        #expect(rec.roofs == ["panels", "off", "doorsOff", "on"])
        #expect(rec.commands.isEmpty)
        // not signed in: nothing
        t.update(model(snap(), signedIn: false))
        t.stepRoof()
        #expect(rec.roofs.count == 4)
    }

    @Test func earthAndJeepButtonsDriveTheMotion() {
        let motion = DashboardMotion()
        let g = JeepGestures(motion: motion, setRoof: { _ in })
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec, gestures: g)
        t.update(model(snap()))
        #expect(t.shownButtons.first { $0.kind == .earth }?.state == .off)

        t.tap(.earth)
        #expect(motion.mapOpen)
        #expect(t.shownButtons.first { $0.kind == .earth }?.state == .on)  // lit right away
        t.tap(.earth)
        #expect(!motion.mapOpen)
        #expect(t.shownButtons.first { $0.kind == .earth }?.state == .off)

        // a divider drag far enough closes it too
        t.tap(.earth)
        g.dividerTravel = 400
        g.began()
        g.changed(CGPoint(x: 12, y: 0))
        g.changed(CGPoint(x: 200, y: 0))
        g.ended(.zero)
        #expect(!motion.mapOpen)
        #expect(motion.dividerDx == 0)

        t.tap(.jeep)
        #expect(motion.mode == .turntable)
        #expect(t.shownButtons.first { $0.kind == .jeep }?.state == .on)
        t.tap(.jeep)
        #expect(motion.mode == .tires)
        t.tap(.jeep)
        #expect(motion.mode == .hero)
        #expect(t.shownButtons.first { $0.kind == .jeep }?.state == .off)

        // the templates keep the gestures' roof current (the strip's step)
        t.update(model(snap(), roof: "off"))
        #expect(g.roof == "off")
        #expect(g.roofIndex == 2)

        // signing out closes the map and goes home
        motion.mapOpen = true
        motion.mode = .tires
        t.update(model(snap(), signedIn: false))
        #expect(!motion.mapOpen)
        #expect(motion.mode == .hero)
    }

    @Test func lockTapWhenUnknownSendsLock() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        t.update(model(snap(locked: nil)))
        t.tap(.lock)
        #expect(rec.commands == [.lock])
    }

    @Test func pendingTapIsIgnored() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        t.update(model(snap(locked: true), pending: [.unlock]))
        t.tap(.lock)
        #expect(rec.commands.isEmpty)
    }

    @Test func moreAndSettingsDoNotPushTwice() {
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        t.update(model(snap()))
        t.showMore()
        t.showMore()
        #expect(fake.pushed.count == 1)
        t.showSettings()
        t.showSettings()
        #expect(fake.pushed.count == 2)
    }

    @Test func moreRowsCallCompletion() throws {
        let fake = FakeCarPlayInterface()
        let rec = Recorder()
        let t = make(fake, rec)
        t.update(model(snap()))
        t.showMore()
        let list = try #require(fake.pushed.last as? CPListTemplate)
        let items = list.sections.flatMap(\.items).compactMap { $0 as? CPListItem }
        #expect(items.map(\.text) == [
            "Climate", "Lights", "Horn", "Tailgate", "Tires", "Charging", "Trip", "Settings",
        ])
        let tappable = items.filter { $0.handler != nil }
        #expect(tappable.map(\.text) == ["Climate", "Lights", "Horn", "Tailgate", "Settings"])
        for item in tappable {
            item.handler?(item) { rec.completions += 1 }
        }
        #expect(rec.completions == tappable.count)
        #expect(rec.commands == [.climateOn, .lights, .horn, .gate])

        // Climate on: the row turns it off, and says so
        t.update(model(snap(), climateOn: true))
        let on = list.sections.flatMap(\.items).compactMap { $0 as? CPListItem }.first { $0.text == "Climate" }
        #expect(on?.detailText == "On")
        on?.handler?(on!) {}
        #expect(rec.commands.last == .climateOff)
    }

    @Test func appsButtonOpensTheGrid() throws {
        if #available(iOS 27.0, *) { return }  // iOS 27: the Apps box (a map panel) instead
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        t.update(model(snap()))
        t.tap(.apps)
        let grid = try #require(fake.pushed.last as? CPGridTemplate)
        #expect(grid.gridButtons.count == 8)
        t.tap(.apps)  // no second push
        #expect(fake.pushed.count == 1)
        #expect(t.mapTemplate.leadingNavigationBarButtons.isEmpty)
    }

    @Test func appsButtonTogglesTheBox() {
        guard #available(iOS 27.0, *) else { return }
        let t = make(FakeCarPlayInterface(), Recorder())
        t.update(model(snap()))
        t.tap(.apps)
        #expect(t.appsBoxOpen)
        t.tap(.apps)
        #expect(!t.appsBoxOpen)
    }

    @Test func allAppsPushesGrid() throws {
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        t.update(model(snap()))
        t.showApps()
        let grid = try #require(fake.pushed.last as? CPGridTemplate)
        #expect(grid.gridButtons.count == 8)
        #expect(grid.gridButtons.map { $0.titleVariants.first ?? "" } == CarPlayModel.appList.map(\.title))
    }

    @Test func dragsReachTheJeep() {
        let rec = Recorder()
        let g = JeepGestures(motion: DashboardMotion(), setRoof: { rec.roofs.append($0) })
        g.send = { rec.calls.append($0) }
        let t = make(FakeCarPlayInterface(), rec, gestures: g)
        t.update(model(snap()))
        t.mapTemplateDidBeginPanGesture(t.mapTemplate)
        t.mapTemplate(t.mapTemplate, didUpdatePanGestureWithTranslation: CGPoint(x: 12, y: 0), velocity: .zero)
        t.mapTemplate(t.mapTemplate, didUpdatePanGestureWithTranslation: CGPoint(x: 32, y: 0), velocity: .zero)
        t.mapTemplate(t.mapTemplate, didEndPanGestureWithVelocity: .zero)
        #expect(rec.calls == ["spin(8.0)", "release()"])

        rec.calls = []
        t.mapTemplateDidBeginZoomGesture(t.mapTemplate)
        t.mapTemplate(t.mapTemplate, didUpdateZoomGestureWithCenter: .zero, scale: 1.2, velocity: 0)
        t.mapTemplate(t.mapTemplate, didEndZoomGestureWithVelocity: 0)
        #expect(rec.calls == ["zoom(1.2)", "zoomEnd()"])
    }

    @Test func appearanceRedrawsTiles() {
        let t = make(FakeCarPlayInterface(), Recorder())
        let m = model(snap())
        t.update(m, dark: true)
        let night = t.mapTemplate.mapButtons.first
        t.update(m, dark: true)
        #expect(t.mapTemplate.mapButtons.first === night)
        t.update(m, dark: false)
        #expect(t.mapTemplate.mapButtons.first !== night)
        #expect(t.mapTemplate.mapButtons.count == 4)
    }

    @Test func reconnectBuildsOnce() {
        let rec = Recorder()
        let first = FakeCarPlayInterface()
        var templates: CarPlayTemplates? = make(first, rec)
        templates?.update(model(snap()))
        templates?.update(model(snap(locked: false)))
        templates?.showMore()
        templates?.showApps()
        templates?.showSettings()
        #expect(first.roots.count == 1)
        weak var old = templates

        // Disconnect, then connect again.
        templates = nil
        #expect(old == nil)
        let second = FakeCarPlayInterface()
        templates = make(second, rec)
        templates?.update(model(snap()))
        #expect(second.roots.count == 1)
        #expect(first.roots.count == 1)
    }
}
