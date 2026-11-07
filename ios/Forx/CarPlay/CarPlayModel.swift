import Foundation

/// The CarPlay map buttons, top to bottom in CarPlay's column (the last one sits in the corner).
nonisolated enum CarPlayButtonKind: Sendable, Equatable {
    case jeep, lock, earth, apps
}

/// Drawn, not animated: map button images are static.
nonisolated enum CarPlayButtonState: Sendable, Equatable {
    case off, on, pending
}

nonisolated struct CarPlayButton: Sendable, Equatable {
    let kind: CarPlayButtonKind
    let state: CarPlayButtonState
    /// The glyph's asset (ios/tools/glyphs): "glyph-jeep-views", "glyph-lock" / "glyph-lock-open",
    /// "glyph-globe", "glyph-apps".
    let symbol: String
    /// The snapshot's lock state (Lock button only): true locked, false unlocked, nil unknown.
    let isLocked: Bool?
}

/// A row of the More list: a command (`action`) or a line of data (`detail`).
nonisolated struct CarPlayRow: Sendable, Equatable {
    let title: String
    let detail: String
    let action: JeepCommand?
}

nonisolated struct CarPlayApp: Sendable, Equatable {
    let title: String
    let url: URL
    let symbol: String
    /// The bundled icon's asset name (`appicon-<id>`).
    let icon: String
}

/// The views the Jeep button cycles: the 3/4 hero, the top view turning on its own, the tires.
nonisolated enum JeepMode: String, Sendable, Equatable, CaseIterable {
    case hero, turntable, tires

    var next: JeepMode {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// What the CarPlay screen shows, worked out from the store's state. Pure: no UIKit, no CarPlay.
nonisolated struct CarPlayModel: Sendable, Equatable {
    let signedIn: Bool
    /// The gear letter in the status row: "P" parked (or unknown), "D" when the ignition is on.
    let gear: String
    /// The range, "186", or "—" when unknown.
    let rangeText: String
    /// "78%", or nil when unknown (no battery glyph then).
    let evText: String?
    /// For the charge port's call-out: "Charging · full by 6:10 PM", "Charging", "Plugged in"; nil otherwise.
    let chargeText: String?
    /// The four pressures for the tires view ("36" or "—"), by FL / FR / RL / RR.
    let tires: [String: String]
    /// "38 minutes ago": how old the snapshot (and so the pressures) is.
    let tiresAgo: String
    /// The roof key ("on", "panels", "off", "doorsOff"), for the Roof bar button and the strip.
    let roofKey: String
    /// The Jeep view on screen.
    let mode: JeepMode
    let mapOpen: Bool
    let message: String?
    let buttons: [CarPlayButton]
    let more: [CarPlayRow]
    let apps: [CarPlayApp]

    static let dash = "—"
    static let gearLetters = ["P", "R", "N", "D"]

    /// The roof steps, bottom to top on the strip (same keys as `AppModel.roof`); the Roof bar
    /// button cycles them in this order too.
    static let roofSteps = ["on", "panels", "off", "doorsOff"]

    /// The step after `roof`, wrapping from "doorsOff" back to "on". Unknown → "panels" (after "on").
    static func nextRoof(after roof: String) -> String {
        let i = roofSteps.firstIndex(of: roof) ?? 0
        return roofSteps[(i + 1) % roofSteps.count]
    }

    /// The strip's step for a roof key: 0 Top on … 3 Doors off (unknown → 0).
    static func roofIndex(_ roof: String) -> Int {
        roofSteps.firstIndex(of: roof) ?? 0
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

    /// The Apps grid, in order; CPGridTemplate holds at most 8. `symbol` is the fallback when
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

    /// `roof` is the chosen roof: "on", "panels", "off" or "doorsOff". `now` and `timeZone` are for
    /// the charging "full by" time and the "minutes ago"; tests pass fixed ones.
    static func make(
        snapshot: JeepSnapshot?, pending: Set<JeepCommand>, climateOn: Bool, message: String?,
        signedIn: Bool, roof: String, mode: JeepMode = .hero, mapOpen: Bool = false,
        now: Date = Date(), timeZone: TimeZone = .current
    ) -> CarPlayModel {
        let s = snapshot
        return CarPlayModel(
            signedIn: signedIn,
            gear: s?.ignitionOn == true ? "D" : "P",
            rangeText: s?.rangeMiles.map(String.init) ?? dash,
            evText: s?.evPercent.map { "\($0)%" },
            chargeText: chargeCallout(s, now: now, timeZone: timeZone),
            tires: tirePressures(s),
            tiresAgo: s.map { ago(from: $0.updatedAt, to: now) } ?? dash,
            roofKey: roofSteps.contains(roof) ? roof : "on",
            mode: mode,
            mapOpen: mapOpen,
            message: message,
            buttons: signedIn ? buttonRow(s, pending: pending, mode: mode, mapOpen: mapOpen) : [],
            more: moreRows(s, climateOn: climateOn, pending: pending, now: now, timeZone: timeZone),
            apps: appList
        )
    }

    // MARK: Map buttons

    /// Jeep (views), Lock (only if the Jeep supports it), Earth (the map), Apps. CarPlay stacks
    /// them bottom-up from the corner, so Apps and Earth sit lowest, in the corner.
    private static func buttonRow(
        _ s: JeepSnapshot?, pending: Set<JeepCommand>, mode: JeepMode, mapOpen: Bool
    ) -> [CarPlayButton] {
        let supported: Set<JeepCommand> = s?.supported ?? []
        var buttons: [CarPlayButton] = []
        buttons.append(CarPlayButton(kind: .jeep, state: mode == .hero ? .off : .on, symbol: "glyph-jeep-views", isLocked: nil))
        if supported.contains(.lock) || supported.contains(.unlock) {
            let busy = pending.contains(.lock) || pending.contains(.unlock)
            let unlocked = s?.locked == false
            let state: CarPlayButtonState = busy ? .pending : (unlocked ? .on : .off)
            let symbol = s?.locked == false ? "glyph-lock-open" : "glyph-lock"
            buttons.append(CarPlayButton(kind: .lock, state: state, symbol: symbol, isLocked: s?.locked))
        }
        buttons.append(CarPlayButton(kind: .earth, state: mapOpen ? .on : .off, symbol: "glyph-globe", isLocked: nil))
        buttons.append(CarPlayButton(kind: .apps, state: .off, symbol: "glyph-apps", isLocked: nil))
        return buttons
    }

    // MARK: Overlay data

    /// What the charge port's call-out says; nil when there's nothing to say (unplugged or unknown).
    private static func chargeCallout(_ s: JeepSnapshot?, now: Date, timeZone: TimeZone) -> String? {
        guard let s else { return nil }
        if s.charging == true {
            guard let minutes = s.chargeMinutesLeft else { return "Charging" }
            return "Charging · full by " + clock(now.addingTimeInterval(TimeInterval(minutes) * 60), timeZone: timeZone)
        }
        if s.pluggedIn == true { return "Plugged in" }
        return nil
    }

    private static func tirePressures(_ s: JeepSnapshot?) -> [String: String] {
        var out: [String: String] = [:]
        for corner in ["FL", "FR", "RL", "RR"] {
            out[corner] = s?.tiresPsi[corner].map { String($0) } ?? dash
        }
        return out
    }

    /// "just now", "1 minute ago", "38 minutes ago", "2 hours ago", "yesterday", "3 days ago".
    static func ago(from then: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(then))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = hours / 24
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    private static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    // MARK: More list

    /// Commands first (only those the Jeep supports), then the data rows.
    private static func moreRows(
        _ s: JeepSnapshot?, climateOn: Bool, pending: Set<JeepCommand>, now: Date, timeZone: TimeZone
    ) -> [CarPlayRow] {
        let supported: Set<JeepCommand> = s?.supported ?? []
        var rows: [CarPlayRow] = []
        if supported.contains(.climateOn) || supported.contains(.climateOff) {
            let busy = pending.contains(.climateOn) || pending.contains(.climateOff)
            rows.append(CarPlayRow(
                title: "Climate", detail: busy ? "…" : (climateOn ? "On" : ""),
                action: climateOn ? .climateOff : .climateOn))
        }
        if supported.contains(.lights) {
            rows.append(CarPlayRow(title: "Lights", detail: "", action: .lights))
        }
        if supported.contains(.horn) {
            rows.append(CarPlayRow(title: "Horn", detail: "", action: .horn))
        }
        if supported.contains(.gate) {
            rows.append(CarPlayRow(title: "Tailgate", detail: "", action: .gate))
        }
        rows.append(CarPlayRow(title: "Tires", detail: tiresDetail(s), action: nil))
        rows.append(CarPlayRow(title: "Charging", detail: chargingDetail(s, now: now, timeZone: timeZone), action: nil))
        let trip = s?.odometerMiles.map { "\(grouped($0)) mi" } ?? dash
        rows.append(CarPlayRow(title: "Trip", detail: trip, action: nil))
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
        if let text = chargeCallout(s, now: now, timeZone: timeZone) { return text }
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
