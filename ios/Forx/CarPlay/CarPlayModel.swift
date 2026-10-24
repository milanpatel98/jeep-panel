import Foundation

/// The CarPlay map buttons, left to right.
nonisolated enum CarPlayButtonKind: Sendable, Equatable {
    case lock, climate, lights, more
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
}

/// A row of the More list. `roofKey` ("on", "panels" or "off") marks the three roof choices
/// (they change the 3D Jeep only).
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
}

/// What the CarPlay screen shows, worked out from the store's state. Pure: no UIKit, no CarPlay.
nonisolated struct CarPlayModel: Sendable, Equatable {
    let signedIn: Bool
    let name: String
    let subtitle: String
    let status: String
    let statusKnown: Bool
    let message: String?
    let buttons: [CarPlayButton]
    let more: [CarPlayRow]
    let apps: [CarPlayApp]

    static let dash = "—"

    /// The Apps tray, in order; CPGridTemplate holds at most 8.
    static let appList: [CarPlayApp] = [
        CarPlayApp(title: "YouTube Music", url: URL(string: "youtubemusic://")!, symbol: "play.circle.fill"),
        CarPlayApp(title: "Spotify", url: URL(string: "spotify://")!, symbol: "waveform"),
        CarPlayApp(title: "Apple Music", url: URL(string: "music://")!, symbol: "music.note"),
        CarPlayApp(title: "Podcasts", url: URL(string: "podcasts://")!, symbol: "antenna.radiowaves.left.and.right"),
        CarPlayApp(title: "Apple Maps", url: URL(string: "maps://")!, symbol: "map.fill"),
        CarPlayApp(title: "Google Maps", url: URL(string: "comgooglemaps://")!, symbol: "mappin.and.ellipse"),
        CarPlayApp(title: "Waze", url: URL(string: "waze://")!, symbol: "car.fill"),
        CarPlayApp(title: "Phone", url: URL(string: "tel://")!, symbol: "phone.fill"),
    ]

    /// `roof` is the chosen roof: "on", "panels" or "off". `now` and `timeZone` are for the
    /// charging "full by" time; tests pass fixed ones.
    static func make(
        snapshot: JeepSnapshot?, pending: Set<JeepCommand>, climateOn: Bool, message: String?,
        signedIn: Bool, roof: String, now: Date = Date(), timeZone: TimeZone = .current
    ) -> CarPlayModel {
        let s = snapshot
        let (status, statusKnown) = statusLine(s)
        return CarPlayModel(
            signedIn: signedIn,
            name: "Milan",
            subtitle: subtitleLine(s),
            status: status,
            statusKnown: statusKnown,
            message: message,
            buttons: signedIn ? buttonRow(s, pending: pending, climateOn: climateOn) : [],
            more: moreRows(s, roof: roof, now: now, timeZone: timeZone),
            apps: appList
        )
    }

    // MARK: Left panel

    /// "78% · 186 mi · Parked"; "—" for unknowns.
    private static func subtitleLine(_ s: JeepSnapshot?) -> String {
        let ev = s?.evPercent.map { "\($0)%" } ?? dash
        let range = s?.rangeMiles.map { "\($0) mi" } ?? "\(dash) mi"
        let gear = s?.ignitionOn == true ? "Driving" : "Parked"
        return "\(ev) · \(range) · \(gear)"
    }

    /// Same wording as the web's attention() (src/state.js), joined with " · ".
    /// Nothing to flag and locked → "Locked · all doors closed". Unknown → "—".
    private static func statusLine(_ s: JeepSnapshot?) -> (String, Bool) {
        guard let s else { return (dash, false) }
        var parts: [String] = []
        let names: [(String, String)] = [
            ("driver", "Driver door"), ("passenger", "Passenger door"),
            ("leftRear", "Rear left door"), ("rightRear", "Rear right door"),
        ]
        let open = names.filter { s.doorsOpen.contains($0.0) }.map { $0.1 }
        if open.count == 4 {
            parts.append("All doors open")
        } else if !open.isEmpty {
            parts.append(open.joined(separator: ", ") + " open")
        }
        if s.tailgateOpen == true { parts.append("Tailgate open") }
        if s.locked == false { parts.append("Unlocked") }
        if !parts.isEmpty { return (parts.joined(separator: " · "), true) }
        if s.locked == true { return ("Locked · all doors closed", true) }
        return (dash, false)
    }

    /// Lock, Climate, Lights (each only if the Jeep supports it), then More, always.
    private static func buttonRow(
        _ s: JeepSnapshot?, pending: Set<JeepCommand>, climateOn: Bool
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
        if supported.contains(.lights) {
            // Momentary: never stays on.
            let state: CarPlayButtonState = pending.contains(.lights) ? .pending : .off
            buttons.append(CarPlayButton(kind: .lights, state: state, symbol: "headlight.high.beam.fill", isLocked: nil))
        }
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
        let roofs: [(String, String)] = [("on", "Top on"), ("panels", "Panels off"), ("off", "Top off")]
        for (key, title) in roofs {
            rows.append(CarPlayRow(title: title, detail: roof == key ? "✓" : "", action: nil, roofKey: key))
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
