import Foundation

/// The CarPlay map buttons, left to right.
nonisolated enum CarPlayButtonKind: Sendable, Equatable {
    case lock, climate, roof, more
}

/// Drawn, not animated: map button images are static.
nonisolated enum CarPlayButtonState: Sendable, Equatable {
    case off, on, pending
}

nonisolated struct CarPlayButton: Sendable, Equatable {
    let kind: CarPlayButtonKind
    let state: CarPlayButtonState
    let symbol: String
    /// The snapshot's lock state (Lock button only): true locked, false unlocked, nil unknown.
    let isLocked: Bool?
    /// The roof step it shows (Roof button only): "on", "panels", "off" or "doorsOff".
    var roof: String? = nil
}

/// A row of the More list. `roofKey` ("on", "panels", "off" or "doorsOff") marks the roof
/// choices (they change the 3D Jeep only).
nonisolated struct CarPlayRow: Sendable, Equatable {
    let title: String
    let detail: String
    let action: JeepCommand?
    let roofKey: String?

    var roof: Bool { roofKey != nil }
}

nonisolated struct CarPlayApp: Sendable, Equatable {
    let title: String
    let url: URL
    let symbol: String
    /// The bundled icon's asset name (`appicon-<id>`).
    let icon: String
}

/// The status glyph's colour.
nonisolated enum CarPlayTint: Sendable, Equatable {
    /// #30D158: locked, all closed.
    case green
    /// #FF9F0A: unlocked, or something open.
    case amber
}

/// What the CarPlay screen shows, worked out from the store's state. Pure: no UIKit, no CarPlay.
nonisolated struct CarPlayModel: Sendable, Equatable {
    let signedIn: Bool
    let name: String
    /// The range, the header's hero number: "186", or "—" when unknown.
    let rangeText: String
    /// "78%", or nil when unknown (no battery glyph then).
    let evText: String?
    /// One word (or two): "Locked", "Unlocked", "Door open", "Tailgate open"; nil when unknown.
    let statusWord: String?
    let statusSymbol: String?
    let statusTint: CarPlayTint?
    /// The roof, for the status line: "Top on", "Panels off", "Top off" or "Doors off".
    let roofWord: String
    /// The roof key ("on", "panels", "off", "doorsOff"), for the roof icon.
    let roofKey: String
    let message: String?
    let buttons: [CarPlayButton]
    let more: [CarPlayRow]
    let apps: [CarPlayApp]

    static let dash = "—"

    /// The roof steps, in the order the Roof button cycles them (same keys as `AppModel.roof`).
    static let roofSteps = ["on", "panels", "off", "doorsOff"]

    /// The step after `roof`, wrapping from "doorsOff" back to "on". Unknown → "panels" (after "on").
    static func nextRoof(after roof: String) -> String {
        let i = roofSteps.firstIndex(of: roof) ?? 0
        return roofSteps[(i + 1) % roofSteps.count]
    }

    /// "Top on", "Panels off", "Top off", "Doors off"; unknown keys read as "Top on".
    static func roofTitle(_ roof: String) -> String {
        switch roof {
        case "panels": "Panels off"
        case "off": "Top off"
        case "doorsOff": "Doors off"
        default: "Top on"
        }
    }

    /// The tray's favourites: the first four apps.
    static var favouriteApps: [CarPlayApp] { Array(appList.prefix(4)) }

    /// The Apps tray, in order; CPGridTemplate holds at most 8. `symbol` is the fallback when
    /// the app's icon isn't bundled (`appicon-<id>`).
    static let appList: [CarPlayApp] = [
        CarPlayApp(title: "YouTube Music", url: URL(string: "youtubemusic://")!, symbol: "play.circle.fill", icon: "appicon-youtubemusic"),
        CarPlayApp(title: "Spotify", url: URL(string: "spotify://")!, symbol: "waveform", icon: "appicon-spotify"),
        CarPlayApp(title: "Apple Music", url: URL(string: "music://")!, symbol: "music.note", icon: "appicon-applemusic"),
        CarPlayApp(title: "Apple Maps", url: URL(string: "maps://")!, symbol: "map.fill", icon: "appicon-applemaps"),
        CarPlayApp(title: "Podcasts", url: URL(string: "podcasts://")!, symbol: "antenna.radiowaves.left.and.right", icon: "appicon-podcasts"),
        CarPlayApp(title: "Google Maps", url: URL(string: "comgooglemaps://")!, symbol: "mappin.and.ellipse", icon: "appicon-googlemaps"),
        CarPlayApp(title: "Waze", url: URL(string: "waze://")!, symbol: "car.fill", icon: "appicon-waze"),
        CarPlayApp(title: "Phone", url: URL(string: "tel://")!, symbol: "phone.fill", icon: "appicon-phone"),
    ]

    /// `roof` is the chosen roof: "on", "panels" or "off". `now` and `timeZone` are for the
    /// charging "full by" time; tests pass fixed ones.
    static func make(
        snapshot: JeepSnapshot?, pending: Set<JeepCommand>, climateOn: Bool, message: String?,
        signedIn: Bool, roof: String, now: Date = Date(), timeZone: TimeZone = .current
    ) -> CarPlayModel {
        let s = snapshot
        let status = statusLine(s)
        return CarPlayModel(
            signedIn: signedIn,
            name: "Milan",
            rangeText: s?.rangeMiles.map(String.init) ?? dash,
            evText: s?.evPercent.map { "\($0)%" },
            statusWord: status?.word,
            statusSymbol: status?.symbol,
            statusTint: status?.tint,
            roofWord: roofTitle(roof),
            roofKey: roof,
            message: message,
            buttons: signedIn ? buttonRow(s, pending: pending, climateOn: climateOn, roof: roof) : [],
            more: moreRows(s, roof: roof, now: now, timeZone: timeZone),
            apps: appList
        )
    }

    // MARK: Left panel

    /// One word and a glyph (`jeep-…` names are Milan's Jeep's own icons in the asset catalogue; the
    /// rest are SF Symbols). An open door wins, then the tailgate, then the lock. Unknown → nil.
    private static func statusLine(_ s: JeepSnapshot?) -> (word: String, symbol: String, tint: CarPlayTint)? {
        guard let s else { return nil }
        if !s.doorsOpen.isEmpty { return ("Door open", "jeep-door-open", .amber) }
        if s.tailgateOpen == true { return ("Tailgate open", "jeep-tailgate-open", .amber) }
        if s.locked == false { return ("Unlocked", "lock.open.fill", .amber) }
        if s.locked == true { return ("Locked", "lock.fill", .green) }
        return nil
    }

    /// Lock, Climate (each only if the Jeep supports it), then Roof and More, always.
    /// Lights lives in the More list. Roof is a mode, not on/off: always the off tile.
    private static func buttonRow(
        _ s: JeepSnapshot?, pending: Set<JeepCommand>, climateOn: Bool, roof: String
    ) -> [CarPlayButton] {
        let supported: Set<JeepCommand> = s?.supported ?? []
        var buttons: [CarPlayButton] = []

        if supported.contains(.lock) || supported.contains(.unlock) {
            let busy = pending.contains(.lock) || pending.contains(.unlock)
            let unlocked = s?.locked == false
            let state: CarPlayButtonState = busy ? .pending : (unlocked ? .on : .off)
            let symbol = s?.locked == false ? "lock.open.fill" : "lock.fill"
            buttons.append(CarPlayButton(kind: .lock, state: state, symbol: symbol, isLocked: s?.locked))
        }
        if supported.contains(.climateOn) || supported.contains(.climateOff) {
            let busy = pending.contains(.climateOn) || pending.contains(.climateOff)
            let state: CarPlayButtonState = busy ? .pending : (climateOn ? .on : .off)
            buttons.append(CarPlayButton(kind: .climate, state: state, symbol: "fan.fill", isLocked: nil))
        }
        let step = roofSteps.contains(roof) ? roof : "on"
        buttons.append(CarPlayButton(kind: .roof, state: .off, symbol: "", isLocked: nil, roof: step))
        buttons.append(CarPlayButton(kind: .more, state: .off, symbol: "ellipsis", isLocked: nil))
        return buttons
    }

    // MARK: More list

    private static func moreRows(
        _ s: JeepSnapshot?, roof: String, now: Date, timeZone: TimeZone
    ) -> [CarPlayRow] {
        let supported: Set<JeepCommand> = s?.supported ?? []
        var rows: [CarPlayRow] = []
        rows.append(CarPlayRow(title: "Tires", detail: tiresDetail(s), action: nil, roofKey: nil))
        rows.append(CarPlayRow(
            title: "Charging", detail: chargingDetail(s, now: now, timeZone: timeZone),
            action: nil, roofKey: nil))
        let roofs: [(String, String)] = [
            ("on", "Top on"), ("panels", "Panels off"), ("off", "Top off"), ("doorsOff", "Doors off"),
        ]
        for (key, title) in roofs {
            rows.append(CarPlayRow(title: title, detail: roof == key ? "✓" : "", action: nil, roofKey: key))
        }
        if supported.contains(.lights) {
            rows.append(CarPlayRow(title: "Lights", detail: "", action: .lights, roofKey: nil))
        }
        if supported.contains(.horn) {
            rows.append(CarPlayRow(title: "Horn", detail: "", action: .horn, roofKey: nil))
        }
        if supported.contains(.gate) {
            rows.append(CarPlayRow(title: "Tailgate", detail: "", action: .gate, roofKey: nil))
        }
        let trip = s?.odometerMiles.map { "\(grouped($0)) mi" } ?? dash
        rows.append(CarPlayRow(title: "Trip", detail: trip, action: nil, roofKey: nil))
        return rows
    }

    /// "FL 35 · FR 35 · RL 34 · RR —" (psi).
    private static func tiresDetail(_ s: JeepSnapshot?) -> String {
        ["FL", "FR", "RL", "RR"].map { corner in
            let psi = s?.tiresPsi[corner].map { String($0) } ?? dash
            return "\(corner) \(psi)"
        }.joined(separator: " · ")
    }

    /// "Charging · full by 6:10 PM", "Charging", "Plugged in", "Unplugged" or "—".
    private static func chargingDetail(_ s: JeepSnapshot?, now: Date, timeZone: TimeZone) -> String {
        guard let s else { return dash }
        if s.charging == true {
            guard let minutes = s.chargeMinutesLeft else { return "Charging" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = "h:mm a"
            return "Charging · full by " + f.string(from: now.addingTimeInterval(TimeInterval(minutes) * 60))
        }
        if s.pluggedIn == true { return "Plugged in" }
        if s.pluggedIn == false { return "Unplugged" }
        return dash
    }

    /// 7671 → "7,671", without depending on the device's locale.
    private static func grouped(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
