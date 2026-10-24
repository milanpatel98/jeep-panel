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

    private func model(_ s: JeepSnapshot?, signedIn: Bool = true) -> CarPlayModel {
        CarPlayModel.make(
            snapshot: s, pending: [], climateOn: false, message: nil,
            signedIn: signedIn, roof: "on", now: now, timeZone: TimeZone(identifier: "UTC")!)
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
        #expect(t.shownButtons.map(\.kind) == [.lock, .climate, .lights, .more])
        #expect(t.mapTemplate.leadingNavigationBarButtons.count == 1)
        #expect(t.mapTemplate.trailingNavigationBarButtons.count == 2)

        // No Lights support: Lights is absent, More stays; same map template, updated in place.
        let noLights = model(snap(supported: [.lock, .unlock, .climateOn, .climateOff]))
        t.update(noLights)
        #expect(fake.roots.count == 1)
        #expect(t.mapTemplate.mapButtons.count == 3)
        #expect(t.shownButtons.map(\.kind) == [.lock, .climate, .more])

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
            "Tires", "Charging", "Top on", "Panels off", "Top off", "Horn", "Tailgate", "Trip",
        ])
        let tappable = items.filter { $0.handler != nil }
        #expect(tappable.map(\.text) == ["Top on", "Panels off", "Top off", "Horn", "Tailgate"])
        for item in tappable {
            item.handler?(item) { rec.completions += 1 }
        }
        #expect(rec.completions == tappable.count)
        #expect(rec.roofs == ["on", "panels", "off"])
        #expect(rec.commands == [.horn, .gate])
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
