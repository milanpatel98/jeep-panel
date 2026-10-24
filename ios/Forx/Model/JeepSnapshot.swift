import Foundation

/// Everything the app shows about the Jeep, parsed from the Uconnect responses and
/// converted to mi / psi. Ports `apply_vehicle_info`, `apply_remote_status` and
/// `parse_location` from py-uconnect's `models.py`.
nonisolated struct JeepSnapshot: Codable, Sendable, Equatable {
    var nickname: String?
    var locked: Bool?
    var doorsOpen: [String]
    var tailgateOpen: Bool?

    var rangeMiles: Int?
    var fuelPercent: Int?
    var evPercent: Int?
    var pluggedIn: Bool?
    var charging: Bool?
    var chargeMinutesLeft: Int?

    var tiresPsi: [String: Int]
    var odometerMiles: Int?

    var latitude: Double?
    var longitude: Double?

    var supported: Set<JeepCommand>
    var updatedAt: Date

    /// Ignition on (running or driving); nil when unknown. "Parked" means not on.
    var ignitionOn: Bool? = nil
    /// Gas-only range (`evInfo.battery.gasRange`), mi.
    var gasRangeMiles: Int? = nil

    enum ParseError: Error { case notAnObject }

    static let milesPerKm = 0.621371
    static let psiPerKPa = 0.145038
    static let psiPerBar = 14.5038

    /// `info` must be a JSON object; `status` and `location` are optional and ignored if
    /// they are not objects. Missing or unexpected fields become nil.
    static func parse(
        info: Data, status: Data?, location: Data?, services: [String], now: Date
    ) throws -> JeepSnapshot {
        guard let p = try JSONSerialization.jsonObject(with: info) as? [String: Any] else {
            throw ParseError.notAnObject
        }
        let r = status.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let loc = location.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }

        // models.py apply_vehicle_info (lines 346-425)
        let batt: [String] = ["evInfo", "battery"]
        let fuel: [String] = ["vehicleInfo", "fuel"]

        // Range: totalRange (L379, gas + electric); otherwise distance_to_empty (L370-374).
        var rangeKm = number(p, batt + ["totalRange"]).map { ($0, str(p, batt + ["distanceToEmpty", "unit"])) }
        if rangeKm == nil {
            let base = number(p, batt + ["distanceToEmpty", "value"]) != nil
                ? batt + ["distanceToEmpty"] : fuel + ["distanceToEmpty"]
            rangeKm = number(p, base + ["value"]).map { ($0, str(p, base + ["unit"])) }
        } else if rangeKm?.1 == nil {
            rangeKm?.1 = str(p, fuel + ["distanceToEmpty", "unit"])
        }

        let charging = equals(p, "CHARGING", batt + ["chargingStatus"])

        // Gas range takes the distance_to_empty unit (L370-378).
        let dte = number(p, batt + ["distanceToEmpty", "value"]) != nil
            ? batt + ["distanceToEmpty"] : fuel + ["distanceToEmpty"]
        let dteUnit = str(p, dte + ["unit"])
        let gasRangeMiles: Int? = number(p, batt + ["gasRange"]).map { Int(miles($0, unit: dteUnit).rounded()) }

        var tires: [String: Int] = [:]
        if let list = value(p, ["vehicleInfo", "tyrePressure"]) as? [Any] {  // L409-423
            var byType: [String: [String: Any]] = [:]
            for case let t as [String: Any] in list {
                if let type = t["type"] as? String { byType[type] = t }
            }
            for key in ["FL", "FR", "RL", "RR"] {
                if let v = number(byType, [key, "pressure", "value"]) {
                    tires[key] = Int(psi(v, unit: str(byType, [key, "pressure", "unit"])).rounded())
                }
            }
        }

        // models.py apply_remote_status (lines 433-454)
        var doorsOpen: [String] = []
        var doorLocks: [Bool?] = []
        if let r {
            for name in ["driver", "passenger", "leftRear", "rightRear"] {
                doorLocks.append(equals(r, "LOCKED", ["doors", name, "status"]))
                if equals(r, "OPEN", ["doors", name, "status"]) == true { doorsOpen.append(name) }
            }
        }
        let locked: Bool? = doorLocks.contains(false) ? false
            : (!doorLocks.isEmpty && !doorLocks.contains { $0 == nil } ? true : nil)

        // Ignition: evInfo.ignitionStatus (L386), replaced by engine.status when the remote
        // status has an engine entry (L449-450).
        let ignitionOn: Bool?
        if let r, r["engine"] != nil {
            ignitionOn = equals(r, "ON", ["engine", "status"])
        } else {
            ignitionOn = equals(p, "ON", ["evInfo", "ignitionStatus"])
        }

        // Each value on its own line, so the initializer below stays cheap to type-check.
        let tailgateOpen: Bool? = r.flatMap { equals($0, "OPEN", ["liftGate", "status"]) }
        let rangeMiles: Int? = rangeKm.map { Int(miles($0.0, unit: $0.1).rounded()) }
        let fuelPercent: Int? = number(p, fuel + ["fuelAmountLevel"]).map { Int($0.rounded()) }  // L383
        let evPercent: Int? = number(p, batt + ["stateOfCharge"]).map { Int($0.rounded()) }  // L360
        let pluggedIn: Bool? = bool(p, batt + ["plugInStatus"])  // L359
        let chargeMinutesLeft: Int? = charging == true
            ? chargeMinutes(p, level: str(p, batt + ["chargingLevel"])) : nil
        // L406-407
        let odometerUnit = str(p, ["vehicleInfo", "odometer", "odometer", "unit"])
        let odometerValue: Double? = number(p, ["vehicleInfo", "odometer", "odometer", "value"])
        let odometerMiles: Int? = odometerValue.map { Int(miles($0, unit: odometerUnit).rounded()) }
        let latitude: Double? = loc.flatMap { number($0, ["latitude"]) }  // parse_location L467
        let longitude: Double? = loc.flatMap { number($0, ["longitude"]) }
        let supported: Set<JeepCommand> = supportedCommands(services: services)

        return JeepSnapshot(
            nickname: nil,
            locked: locked,
            doorsOpen: doorsOpen,
            tailgateOpen: tailgateOpen,
            rangeMiles: rangeMiles,
            fuelPercent: fuelPercent,
            evPercent: evPercent,
            pluggedIn: pluggedIn,
            charging: charging,  // L354
            chargeMinutesLeft: chargeMinutesLeft,
            tiresPsi: tires,
            odometerMiles: odometerMiles,
            latitude: latitude,
            longitude: longitude,
            supported: supported,
            updatedAt: now,
            ignitionOn: ignitionOn,
            gasRangeMiles: gasRangeMiles
        )
    }

    // MARK: Units

    private static func miles(_ v: Double, unit: String?) -> Double {
        unit?.lowercased() == "mi" ? v : v * milesPerKm
    }

    private static func psi(_ v: Double, unit: String?) -> Double {
        switch unit?.lowercased() {
        case "psi": v
        case "bar": v * psiPerBar
        default: v * psiPerKPa
        }
    }

    /// Minutes to full for the reported charge level (L402-404); an unknown level takes the
    /// fastest level that reports a non-negative time. -1 means not available.
    private static func chargeMinutes(_ p: [String: Any], level: String?) -> Int? {
        func minutes(_ n: Int) -> Int? {
            number(p, ["evInfo", "battery", "timeToFullyChargeL\(n)"]).map { Int($0.rounded()) }.flatMap { $0 >= 0 ? $0 : nil }
        }
        switch level {
        case "LEVEL_1": return minutes(1)
        case "LEVEL_2": return minutes(2)
        case "LEVEL_3": return minutes(3)
        default: return minutes(3) ?? minutes(2) ?? minutes(1)
        }
    }
}

// MARK: Loose JSON access (models.py `_get`, `get_str`, `get_float`, `get_eq`)

/// `_get`: walk dictionaries by key; the string "null" counts as missing.
private nonisolated func value(_ root: Any?, _ keys: [String]) -> Any? {
    var current = root
    for key in keys {
        guard let dict = current as? [String: Any] else { return nil }
        current = dict[key]
    }
    if current is NSNull { return nil }
    if let s = current as? String, s == "null" { return nil }
    return current
}

private nonisolated func str(_ root: Any?, _ keys: [String]) -> String? {
    switch value(root, keys) {
    case let s as String: return s
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        return n.stringValue
    default: return nil
    }
}

private nonisolated func number(_ root: Any?, _ keys: [String]) -> Double? {
    switch value(root, keys) {
    case let s as String:
        guard let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite else { return nil }
        return d
    case let n as NSNumber:
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? nil : n.doubleValue
    default: return nil
    }
}

private nonisolated func bool(_ root: Any?, _ keys: [String]) -> Bool? {
    jsonBool(value(root, keys))
}

/// `get_eq`: case-insensitive match; nil if missing, empty or "NA".
private nonisolated func equals(_ root: Any?, _ expected: String, _ keys: [String]) -> Bool? {
    guard let s = str(root, keys), !s.isEmpty, s.uppercased() != "NA" else { return nil }
    return s.uppercased() == expected.uppercased()
}
