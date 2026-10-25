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
        roof: String = "on"
    ) -> CarPlayModel {
        CarPlayModel.make(
            snapshot: s, pending: pending, climateOn: climateOn, message: nil,
            signedIn: signedIn, roof: roof, now: now, timeZone: TimeZone(identifier: "UTC")!)
    }

    private func make(_ fake: FakeCarPlayInterface, _ rec: Recorder) -> CarPlayTemplates {
        CarPlayTemplates(
            interface: fake,
            open: { rec.urls.append($0) },
            perform: { rec.commands.append($0) },
            setRoof: { rec.roofs.append($0) },
            email: { "milan@example.com" })
    }

    @Test func mapButtonsMatchModel() {
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        let full = model(snap())
        t.update(full)
        #expect(fake.roots.count == 1)
        #expect(fake.roots.first === t.mapTemplate)
        #expect(t.mapTemplate.mapButtons.count == 4)
        #expect(t.shownButtons.map(\.kind) == [.lock, .climate, .roof, .more])
        #expect(t.mapTemplate.leadingNavigationBarButtons.count == 1)
        #expect(t.mapTemplate.trailingNavigationBarButtons.count == 1)  // Apps; Settings is in More
        #expect(t.mapTemplate.automaticallyHidesNavigationBar)

        // The same model again reassigns nothing (no flicker).
        let mapBefore = t.mapTemplate.mapButtons
        let barBefore = t.mapTemplate.trailingNavigationBarButtons
        t.update(full)
        #expect(t.mapTemplate.mapButtons.first === mapBefore.first)
        #expect(t.mapTemplate.trailingNavigationBarButtons.first === barBefore.first)

        // No Climate support: Climate is absent, Roof and More stay; same map template, updated in place.
        let noClimate = model(snap(supported: [.lock, .unlock, .lights]))
        t.update(noClimate)
        #expect(fake.roots.count == 1)
        #expect(t.mapTemplate.mapButtons.count == 3)
        #expect(t.shownButtons.map(\.kind) == [.lock, .roof, .more])

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

    @Test func roofTapCyclesTheRoof() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        var roof = "on"
        for _ in 0..<4 {
            t.update(model(snap(), roof: roof))
            t.tap(.roof)
            roof = rec.roofs.last ?? roof
        }
        #expect(rec.roofs == ["panels", "off", "doorsOff", "on"])
        #expect(rec.commands.isEmpty)
        // the tile is redrawn for each roof
        t.update(model(snap(), roof: "on"))
        let before = t.mapTemplate.mapButtons[2]
        t.update(model(snap(), roof: "panels"))
        #expect(t.mapTemplate.mapButtons[2] !== before)
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
        t.update(model(snap(), pending: [.climateOff], climateOn: true))
        #expect(t.shownButtons.first { $0.kind == .climate }?.state == .pending)
        t.tap(.climate)
        #expect(rec.commands.isEmpty)
    }

    @Test func moreAndSettingsDoNotPushTwice() {
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        t.update(model(snap()))
        t.tap(.more)
        t.tap(.more)
        #expect(fake.pushed.count == 1)
        t.showSettings()
        t.showSettings()
        #expect(fake.pushed.count == 2)
    }

    @Test func searchOpensAppleMaps() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        t.update(model(snap()))
        t.tapSearch()
        #expect(rec.urls == [URL(string: "maps://")!])
    }

    @Test func moreRowsCallCompletion() throws {
        let fake = FakeCarPlayInterface()
        let rec = Recorder()
        let t = make(fake, rec)
        t.update(model(snap()))
        t.tap(.more)
        let list = try #require(fake.pushed.last as? CPListTemplate)
        let items = list.sections.flatMap(\.items).compactMap { $0 as? CPListItem }
        #expect(items.map(\.text) == [
            "Tires", "Charging", "Top on", "Panels off", "Top off", "Doors off", "Lights", "Horn", "Tailgate", "Trip",
        ])
        let tappable = items.filter { $0.handler != nil }
        #expect(tappable.map(\.text) == ["Top on", "Panels off", "Top off", "Doors off", "Lights", "Horn", "Tailgate"])
        for item in tappable {
            item.handler?(item) { rec.completions += 1 }
        }
        #expect(rec.completions == tappable.count)
        #expect(rec.roofs == ["on", "panels", "off", "doorsOff"])
        #expect(rec.commands == [.lights, .horn, .gate])
    }

    @Test func trayModeSwapsMapButtonsToFavourites() {
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        t.update(model(snap()))
        #expect(t.mapTemplate.trailingNavigationBarButtons.count == 1)
        t.toggleTray()
        #expect(t.tray.isOpen)
        #expect(t.shownButtons.isEmpty)
        #expect(t.shownApps.map(\.title) == ["YouTube Music", "Spotify", "Apple Music", "Apple Maps"])
        #expect(t.mapTemplate.mapButtons.count == 4)
        // "All apps" joins Search on the leading side
        #expect(t.mapTemplate.leadingNavigationBarButtons.count == 2)
        // The same state again reassigns nothing.
        let before = t.mapTemplate.mapButtons
        t.update(model(snap()))
        #expect(t.mapTemplate.mapButtons.first === before.first)
        // Closing brings the command buttons back.
        t.toggleTray()
        #expect(!t.tray.isOpen)
        #expect(t.shownButtons.map(\.kind) == [.lock, .climate, .roof, .more])
        #expect(t.mapTemplate.leadingNavigationBarButtons.count == 1)
    }

    @Test func favouriteTapOpensURLAndClosesTray() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        t.update(model(snap()))
        t.toggleTray()
        t.tapApp(1)
        #expect(rec.urls == [URL(string: "spotify://")!])
        #expect(!t.tray.isOpen)
        #expect(t.shownApps.isEmpty)
        #expect(t.shownButtons.map(\.kind) == [.lock, .climate, .roof, .more])
    }

    @Test func commandClosesTray() {
        let rec = Recorder()
        let t = make(FakeCarPlayInterface(), rec)
        t.update(model(snap()))
        t.tray.open()
        t.tap(.lock)
        #expect(!t.tray.isOpen)
        #expect(rec.commands == [.unlock])
    }

    @Test func allAppsPushesGrid() throws {
        let fake = FakeCarPlayInterface()
        let t = make(fake, Recorder())
        t.update(model(snap()))
        t.toggleTray()
        t.showApps()
        let grid = try #require(fake.pushed.last as? CPGridTemplate)
        #expect(grid.gridButtons.count == 8)
        #expect(grid.gridButtons.map { $0.titleVariants.first ?? "" } == CarPlayModel.appList.map(\.title))
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
        templates?.tap(.more)
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
