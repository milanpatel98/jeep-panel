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

/// JeepSnapshot → the patch for `window.jeepNative.apply(patch)` (src/native.js contract).
/// Only keys the snapshot can fill are sent; anything unknown is JSON null, never a guess.
/// `name`, `gear`, `trail`, `climate` and the rest stay the web's own defaults.
/// `timeZone` is for `battery.fullBy`; tests pass a fixed one.
/// Every value is JSONSerialization-valid (String, NSNumber, NSNull, Array, Dictionary).
nonisolated func panelPatch(
    _ s: JeepSnapshot?, pending: Set<JeepCommand>, offline: Bool, message: String?,
    messageId: Int, now: Date, timeZone: TimeZone = .current
) -> [String: Any] {
    let hasPlace = s?.latitude?.isFinite == true && s?.longitude?.isFinite == true
    let pendingKeys = Set(pending.map(panelKey))
    let panelKeys = ["lock", "climate", "lights", "horn", "gate"]
    var patch: [String: Any] = [
        "locked": json(s?.locked),
        "battery": [
            "pct": json(s?.evPercent),
            "miles": json(s?.rangeMiles),
            "charging": json(s?.charging),
            "fullBy": fullBy(s, now: now, timeZone: timeZone),
        ] as [String: Any],
        "gate": json(s?.tailgateOpen),
        "fuel": ["miles": NSNull()] as [String: Any],
        "odometer": json(s?.odometerMiles),
        "location": [
            "lat": hasPlace ? json(s?.latitude) : NSNull() as Any,
            "lng": hasPlace ? json(s?.longitude) : NSNull() as Any,
        ] as [String: Any],
        "pending": [String: Bool](uniqueKeysWithValues: panelKeys.map { ($0, pendingKeys.contains($0)) }),
        "supported": Set((s?.supported ?? []).map(panelKey)).sorted(),
        "updated": s.map { updatedCopy(since: $0.updatedAt, now: now) } ?? "",
        "offline": offline,
        "message": json(message),
        "messageId": messageId,
    ]
    // Doors only when a remote status came back (locked is its proxy); otherwise the web keeps its value.
    if let s, s.locked != nil {
        let open = Set(s.doorsOpen)
        patch["doors"] = [
            "FL": open.contains("driver"), "FR": open.contains("passenger"),
            "BL": open.contains("leftRear"), "BR": open.contains("rightRear"),
        ] as [String: Bool]
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
