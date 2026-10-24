import Foundation
import Testing
@testable import Forx

struct SnapshotCacheTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotCacheTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    private func sample() -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: true, doorsOpen: ["driver"], tailgateOpen: false,
            rangeMiles: 186, fuelPercent: 60, evPercent: 78, pluggedIn: true, charging: false,
            chargeMinutesLeft: nil, tiresPsi: ["FL": 35, "FR": 35], odometerMiles: 7671,
            latitude: 0.0, longitude: 0.0, supported: [.lock, .unlock, .horn],
            updatedAt: Date(timeIntervalSince1970: 1_792_843_200))
    }

    @Test func roundTrip() throws {
        let cache = SnapshotCache(url: tempURL())
        #expect(cache.load() == nil)
        try cache.save(sample())
        #expect(cache.load() == sample())
    }

    @Test func loadsLastSnapshotOffline() throws {
        let url = tempURL()
        try SnapshotCache(url: url).save(sample())
        #expect(SnapshotCache(url: url).load() == sample())
    }
}
