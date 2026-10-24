import Foundation

/// The panel's name for a command (`supported` / `pending` keys in src/state.js).
nonisolated func panelKey(_ cmd: JeepCommand) -> String {
    switch cmd {
    case .lock, .unlock: "lock"
    case .climateOn, .climateOff: "climate"
    case .lights: "lights"
    case .horn: "horn"
    case .gate: "gate"
    }
}

nonisolated enum PanelPatch {
    /// Data older than this is dimmed (`stale`), like data shown while offline.
    static let staleAfter: TimeInterval = 10 * 60
}

/// JeepSnapshot → the patch for `window.jeepNative.apply(patch)` (src/native.js contract).
/// Only keys the snapshot can fill are sent; anything unknown is JSON null, never a guess.
/// `name`, `gear`, `trail` and the rest stay the web's own defaults; of `climate` only `on`
/// is sent (`climateOn`: the store's view after a confirmed Climate On/Off).
/// `timeZone` is for `battery.fullBy`; tests pass a fixed one.
/// Every value is JSONSerialization-valid (String, NSNumber, NSNull, Array, Dictionary).
/// Built one key at a time so the compiler never has to type-check one big literal.
nonisolated func panelPatch(
    _ s: JeepSnapshot?, pending: Set<JeepCommand>, offline: Bool, message: String?,
    messageId: Int, climateOn: Bool = false, now: Date, timeZone: TimeZone = .current
) -> [String: Any] {
    var patch: [String: Any] = [:]
    patch["locked"] = json(s?.locked)

    var battery: [String: Any] = [:]
    battery["pct"] = json(s?.evPercent)
    battery["miles"] = json(s?.rangeMiles)
    battery["charging"] = json(s?.charging)
    battery["fullBy"] = fullBy(s, now: now, timeZone: timeZone)
    patch["battery"] = battery

    var fuel: [String: Any] = [:]
    fuel["pct"] = json(s?.fuelPercent)
    fuel["miles"] = json(s?.gasRangeMiles)
    patch["fuel"] = fuel

    var tires: [String: Any] = [:]
    for corner in ["FL", "FR", "RL", "RR"] {
        tires[corner] = json(s?.tiresPsi[corner])
    }
    patch["tires"] = tires

    patch["gate"] = json(s?.tailgateOpen)
    patch["odometer"] = json(s?.odometerMiles)
    patch["climate"] = ["on": climateOn] as [String: Any]

    let hasPlace = s?.latitude?.isFinite == true && s?.longitude?.isFinite == true
    var location: [String: Any] = [:]
    location["lat"] = hasPlace ? json(s?.latitude) : NSNull() as Any
    location["lng"] = hasPlace ? json(s?.longitude) : NSNull() as Any
    patch["location"] = location

    let pendingKeys = Set(pending.map(panelKey))
    var pendingFlags: [String: Bool] = [:]
    for key in ["lock", "climate", "lights", "horn", "gate"] {
        pendingFlags[key] = pendingKeys.contains(key)
    }
    patch["pending"] = pendingFlags
    let supported: Set<JeepCommand> = s?.supported ?? []
    patch["supported"] = Set(supported.map(panelKey)).sorted()

    patch["updated"] = s.map { updatedCopy(since: $0.updatedAt, now: now) } ?? ""
    patch["offline"] = offline
    let age: TimeInterval? = s.map { now.timeIntervalSince($0.updatedAt) }
    patch["stale"] = (age ?? 0) > PanelPatch.staleAfter
    patch["message"] = json(message)
    patch["messageId"] = messageId

    // Doors only when a remote status came back (locked is its proxy); otherwise the web keeps its value.
    if let s, s.locked != nil {
        let open = Set(s.doorsOpen)
        var doors: [String: Bool] = [:]
        doors["FL"] = open.contains("driver")
        doors["FR"] = open.contains("passenger")
        doors["BL"] = open.contains("leftRear")
        doors["BR"] = open.contains("rightRear")
        patch["doors"] = doors
    }
    return patch
}

/// "6:10 AM": the clock time charging should finish, or null when not charging or unknown.
private nonisolated func fullBy(_ s: JeepSnapshot?, now: Date, timeZone: TimeZone) -> Any {
    guard let s, s.charging == true, let minutes = s.chargeMinutesLeft else { return NSNull() }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    f.dateFormat = "h:mm a"
    return f.string(from: now.addingTimeInterval(TimeInterval(minutes) * 60))
}

/// "Updated now" under 60 s, then "Updated N min ago", then "Updated N h ago" (rounded down).
nonisolated func updatedCopy(since: Date, now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(since))
    if seconds < 60 { return "Updated now" }
    if seconds < 3600 { return "Updated \(seconds / 60) min ago" }
    return "Updated \(seconds / 3600) h ago"
}

private nonisolated func json<T>(_ value: T?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}
