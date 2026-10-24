import Foundation

/// Local notifications the app can raise (each can be switched off in Settings).
nonisolated enum Alert: String, CaseIterable, Sendable {
    case leftUnlocked, lowTire, lowRange, chargingDone

    static let unlockedSeconds: TimeInterval = 10 * 60
    static let lowTirePsi = 32
    static let lowRangeMiles = 40
}

/// Which alerts apply to `current`, in `Alert.allCases` order.
/// - `unlockedSince`: when the caller first saw the Jeep unlocked while parked (the snapshot
///   has no gear, so "parked" is the caller's call); nil if it isn't.
/// - The rules are levels, not edges (except `chargingDone`): the caller decides how often
///   to repeat a notification.
nonisolated func alerts(
    previous: JeepSnapshot?, current: JeepSnapshot, unlockedSince: Date?, now: Date
) -> [Alert] {
    var out: [Alert] = []
    if current.locked == false, let since = unlockedSince,
       now.timeIntervalSince(since) >= Alert.unlockedSeconds {
        out.append(.leftUnlocked)
    }
    if current.tiresPsi.values.contains(where: { $0 < Alert.lowTirePsi }) {
        out.append(.lowTire)
    }
    if let range = current.rangeMiles, range < Alert.lowRangeMiles {
        out.append(.lowRange)
    }
    if previous?.charging == true, current.charging == false, current.pluggedIn == true {
        out.append(.chargingDone)
    }
    return out
}
