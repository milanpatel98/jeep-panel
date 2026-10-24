import Foundation
import Testing
@testable import Forx

struct PanelPatchTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    private func snap(
        locked: Bool? = true, range: Int? = 186, ev: Int? = 78, charging: Bool? = false,
        odometer: Int? = 7671, lat: Double? = 0.0, lng: Double? = 0.0,
        supported: Set<JeepCommand> = [], age: TimeInterval = 0,
        doorsOpen: [String] = [], tailgate: Bool? = nil, chargeMinutes: Int? = nil
    ) -> JeepSnapshot {
        JeepSnapshot(
            nickname: nil, locked: locked, doorsOpen: doorsOpen, tailgateOpen: tailgate,
            rangeMiles: range, fuelPercent: nil, evPercent: ev, pluggedIn: nil, charging: charging,
            chargeMinutesLeft: chargeMinutes, tiresPsi: [:], odometerMiles: odometer,
            latitude: lat, longitude: lng, supported: supported,
            updatedAt: now.addingTimeInterval(-age))
    }

    private func patch(
        _ s: JeepSnapshot?, pending: Set<JeepCommand> = [], offline: Bool = false,
        message: String? = nil, messageId: Int = 0
    ) -> [String: Any] {
        panelPatch(
            s, pending: pending, offline: offline, message: message, messageId: messageId, now: now,
            timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func supportedMapsToPanelKeys() {
        let p = patch(snap(supported: [.lock, .unlock, .horn]))
        #expect(p["supported"] as? [String] == ["horn", "lock"])
        let all = patch(snap(supported: Set(JeepCommand.allCases)))
        #expect(all["supported"] as? [String] == ["climate", "gate", "horn", "lights", "lock"])
    }

    @Test func updatedCopy() {
        #expect(patch(snap(age: 30))["updated"] as? String == "Updated now")
        #expect(patch(snap(age: 59))["updated"] as? String == "Updated now")
        #expect(patch(snap(age: 60))["updated"] as? String == "Updated 1 min ago")
        #expect(patch(snap(age: 180))["updated"] as? String == "Updated 3 min ago")
        #expect(patch(snap(age: 7200))["updated"] as? String == "Updated 2 h ago")
        #expect(patch(nil)["updated"] as? String == "")
    }

    @Test func nilSnapshotGivesNulls() {
        let p = patch(nil)
        #expect(p["locked"] is NSNull)
        #expect(p["odometer"] is NSNull)
        #expect(p["message"] is NSNull)
        let battery = p["battery"] as? [String: Any]
        #expect(battery?["pct"] is NSNull)
        #expect(battery?["miles"] is NSNull)
        #expect(battery?["charging"] is NSNull)
        #expect((p["fuel"] as? [String: Any])?["miles"] is NSNull)
        let location = p["location"] as? [String: Any]
        #expect(location?["lat"] is NSNull)
        #expect(location?["lng"] is NSNull)
        #expect(p["supported"] as? [String] == [])
        // web owns these
        #expect(p["name"] == nil && p["gear"] == nil && p["trail"] == nil)
    }

    @Test func snapshotValues() {
        let p = patch(snap(supported: [.lock]), offline: true, message: "Jeep didn't answer. Try again.")
        #expect(p["locked"] as? Bool == true)
        #expect(p["odometer"] as? Int == 7671)
        let battery = p["battery"] as? [String: Any]
        #expect(battery?["pct"] as? Int == 78)
        #expect(battery?["miles"] as? Int == 186)
        #expect(battery?["charging"] as? Bool == false)
        let location = p["location"] as? [String: Any]
        #expect(location?["lat"] as? Double == 0.0)
        #expect(location?["lng"] as? Double == 0.0)
        #expect(p["offline"] as? Bool == true)
        #expect(p["message"] as? String == "Jeep didn't answer. Try again.")
    }

    @Test func locationNeedsBothCoordinates() {
        let location = patch(snap(lat: 0.0, lng: nil))["location"] as? [String: Any]
        #expect(location?["lat"] is NSNull)
        #expect(location?["lng"] is NSNull)
    }

    @Test func pendingMapsToPanelKeys() {
        let p = patch(snap(), pending: [.unlock, .climateOff])["pending"] as? [String: Bool]
        #expect(p == ["lock": true, "climate": true, "lights": false, "horn": false, "gate": false])
    }

    @Test func messageIdPassesThrough() {
        #expect(patch(snap(), messageId: 7)["messageId"] as? Int == 7)
        #expect(patch(nil, messageId: 0)["messageId"] as? Int == 0)
    }

    @Test func patchIsValidJSON() throws {
        let full = patch(snap(supported: Set(JeepCommand.allCases)), pending: [.horn], message: "Hi", messageId: 3)
        #expect(JSONSerialization.isValidJSONObject(full))
        #expect(JSONSerialization.isValidJSONObject(patch(nil)))
        _ = try JSONSerialization.data(withJSONObject: full)
    }

    @Test func doorsSentWhenStatusKnown() {
        let doors = patch(snap(locked: false, doorsOpen: ["passenger"]))["doors"] as? [String: Bool]
        #expect(doors == ["FL": false, "FR": true, "BL": false, "BR": false])
        let all = patch(snap(doorsOpen: ["driver", "passenger", "leftRear", "rightRear"]))["doors"] as? [String: Bool]
        #expect(all == ["FL": true, "FR": true, "BL": true, "BR": true])
    }

    @Test func doorsOmittedWhenStatusUnknown() {
        #expect(patch(snap(locked: nil))["doors"] == nil)
        #expect(patch(nil)["doors"] == nil)
    }

    @Test func gateFromTailgate() {
        #expect(patch(snap(tailgate: true))["gate"] as? Bool == true)
        #expect(patch(snap(tailgate: false))["gate"] as? Bool == false)
        #expect(patch(snap(tailgate: nil))["gate"] is NSNull)
        #expect(patch(nil)["gate"] is NSNull)
    }

    @Test func fullByWhileCharging() {
        // now is 12:00 UTC; + 150 min = 2:30 PM
        let charging = patch(snap(charging: true, chargeMinutes: 150))["battery"] as? [String: Any]
        #expect(charging?["fullBy"] as? String == "2:30 PM")
        let unknown = patch(snap(charging: true, chargeMinutes: nil))["battery"] as? [String: Any]
        #expect(unknown?["fullBy"] is NSNull)
        let idle = patch(snap(charging: false, chargeMinutes: 150))["battery"] as? [String: Any]
        #expect(idle?["fullBy"] is NSNull)
        #expect((patch(nil)["battery"] as? [String: Any])?["fullBy"] is NSNull)
    }

    @Test func patchWithDoorsIsValidJSON() {
        let p = patch(snap(charging: true, doorsOpen: ["driver"], tailgate: true, chargeMinutes: 30))
        #expect(JSONSerialization.isValidJSONObject(p))
    }
}
