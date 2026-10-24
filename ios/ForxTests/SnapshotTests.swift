import Foundation
import Testing
@testable import Forx

struct SnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    @Test func parsesFixture() throws {
        let s = try JeepSnapshot.parse(
            info: Fixture.data("vehicle_info"),
            status: Fixture.data("remote_status"),
            location: nil,
            services: enabledServices(fromJSON: Fixture.data("services")),
            now: now
        )
        // totalRange 300 km x 0.621371 = 186.41 -> 186
        #expect(s.rangeMiles == 186)
        // odometer 12345.6 km x 0.621371 = 7671.2 -> 7671
        #expect(s.odometerMiles == 7671)
        // 241 kPa x 0.145038 = 34.95 -> 35; 238 -> 34.52 -> 35; 234 -> 33.94 -> 34
        #expect(s.tiresPsi == ["FL": 35, "FR": 35, "RL": 34])
        #expect(s.fuelPercent == 60)
        #expect(s.evPercent == 78)
        #expect(s.pluggedIn == false)
        #expect(s.charging == false)
        #expect(s.chargeMinutesLeft == nil)
        #expect(s.locked == true)
        #expect(s.doorsOpen.isEmpty)
        #expect(s.tailgateOpen == false)
        #expect(s.latitude == nil && s.longitude == nil)
        #expect(s.supported == [.lock, .unlock, .horn, .climateOn, .climateOff])
        #expect(s.updatedAt == now)
        // gasRange 260 km x 0.621371 = 161.56 -> 162
        #expect(s.gasRangeMiles == 162)
        #expect(s.ignitionOn == false)
    }

    @Test func ignitionFromInfoThenRemoteStatus() throws {
        func ignition(info: String, status: String?) throws -> Bool? {
            try JeepSnapshot.parse(
                info: Data(info.utf8), status: status.map { Data($0.utf8) }, location: nil,
                services: [], now: now
            ).ignitionOn
        }
        let off = #"{"evInfo": {"ignitionStatus": "OFF"}}"#
        let on = #"{"evInfo": {"ignitionStatus": "ON"}}"#
        #expect(try ignition(info: off, status: nil) == false)
        #expect(try ignition(info: on, status: nil) == true)
        #expect(try ignition(info: "{}", status: nil) == nil)
        // models.py L449-450: an engine entry in the remote status wins
        #expect(try ignition(info: off, status: #"{"engine": {"status": "ON"}}"#) == true)
        #expect(try ignition(info: on, status: #"{"engine": {"status": "OFF"}}"#) == false)
        #expect(try ignition(info: on, status: #"{"engine": {}}"#) == nil)
        #expect(try ignition(info: on, status: #"{"doors": {}}"#) == true)
    }

    @Test func gasRangeTakesDistanceToEmptyUnit() throws {
        let mi = #"{"evInfo": {"battery": {"gasRange": "200", "distanceToEmpty": {"value": "20", "unit": "mi"}}}}"#
        #expect(try JeepSnapshot.parse(info: Data(mi.utf8), status: nil, location: nil, services: [], now: now)
            .gasRangeMiles == 200)
        let none = #"{"evInfo": {"battery": {}}}"#
        #expect(try JeepSnapshot.parse(info: Data(none.utf8), status: nil, location: nil, services: [], now: now)
            .gasRangeMiles == nil)
    }

    @Test func nullFieldsStayNil() throws {
        let s = try JeepSnapshot.parse(
            info: Fixture.data("vehicle_info"), status: nil, location: nil, services: [], now: now)
        #expect(s.tiresPsi["RR"] == nil)
        #expect(s.tiresPsi.count == 3)
        #expect(s.locked == nil)
        #expect(s.tailgateOpen == nil)
        #expect(s.doorsOpen.isEmpty)
        #expect(s.supported.isEmpty)
        #expect(s.rangeMiles != nil && s.fuelPercent != nil && s.odometerMiles != nil)
    }

    @Test func unknownJSONDoesNotThrow() throws {
        let s = try JeepSnapshot.parse(
            info: Data("{}".utf8), status: Data("{}".utf8), location: Data("{}".utf8),
            services: [], now: now)
        #expect(s.nickname == nil && s.locked == nil && s.tailgateOpen == nil)
        #expect(s.rangeMiles == nil && s.fuelPercent == nil && s.evPercent == nil)
        #expect(s.pluggedIn == nil && s.charging == nil && s.chargeMinutesLeft == nil)
        #expect(s.tiresPsi.isEmpty && s.doorsOpen.isEmpty)
        #expect(s.odometerMiles == nil && s.latitude == nil && s.longitude == nil)
    }

    @Test func notAnObjectThrows() {
        #expect(throws: (any Error).self) {
            try JeepSnapshot.parse(info: Data("[]".utf8), status: nil, location: nil, services: [], now: now)
        }
    }

    @Test func lockedFollowsDoors() throws {
        func locked(_ driver: String, _ other: String) throws -> Bool? {
            let status = """
            {"doors":{"driver":{"status":"\(driver)"},"passenger":{"status":"LOCKED"},
            "leftRear":{"status":"LOCKED"},"rightRear":{"status":"\(other)"}}}
            """
            return try JeepSnapshot.parse(
                info: Data("{}".utf8), status: Data(status.utf8), location: nil, services: [], now: now
            ).locked
        }
        #expect(try locked("UNLOCKED", "LOCKED") == false)
        #expect(try locked("LOCKED", "NA") == nil)
        #expect(try locked("UNLOCKED", "NA") == false)
    }

    @Test func openDoorsAndGate() throws {
        let status = """
        {"doors":{"driver":{"status":"OPEN"},"passenger":{"status":"LOCKED"},
        "leftRear":{"status":"LOCKED"},"rightRear":{"status":"OPEN"}},"liftGate":{"status":"OPEN"}}
        """
        let s = try JeepSnapshot.parse(
            info: Data("{}".utf8), status: Data(status.utf8), location: nil, services: [], now: now)
        #expect(s.doorsOpen == ["driver", "rightRear"])
        #expect(s.tailgateOpen == true)
    }

    @Test func chargingMinutesAndLocation() throws {
        let info = """
        {"evInfo":{"battery":{"chargingStatus":"CHARGING","chargingLevel":"LEVEL_2",
        "timeToFullyChargeL1":"600","timeToFullyChargeL2":150,"timeToFullyChargeL3":"-1"}}}
        """
        let loc = #"{"latitude":"1.5","longitude":-2.25}"#
        let s = try JeepSnapshot.parse(
            info: Data(info.utf8), status: nil, location: Data(loc.utf8), services: [], now: now)
        #expect(s.charging == true)
        #expect(s.chargeMinutesLeft == 150)
        #expect(s.latitude == 1.5)
        #expect(s.longitude == -2.25)
    }
}
