import CoreFoundation
import Foundation

/// Remote commands the app sends, ported from py-uconnect's `command.py`.
/// The raw value is the command name POSTed as `{"command": <name>, "pinAuth": <token>}`.
nonisolated enum JeepCommand: String, CaseIterable, Sendable, Codable {
    case lock = "RDL"
    case unlock = "RDU"
    case climateOn = "REON"
    case climateOff = "REOFF"
    case lights = "ROLIGHTS"
    case horn = "HBLF"
    case gate = "ROLIFTGATEUNLOCK"

    /// `/<apiVersion>/accounts/<uid>/vehicles/<vin>/<urlSuffix>`. The eight classic
    /// commands use v1; the liftgate is one of the newer v2 remote operations.
    var apiVersion: String {
        switch self {
        case .gate: "v2"
        case .lock, .unlock, .climateOn, .climateOff, .lights, .horn: "v1"
        }
    }

    var urlSuffix: String { "remote/" }

    /// Services that enable the command. None of these declares a `services`
    /// tuple in `command.py`, so it defaults to the command name.
    var services: [String] { [rawValue] }

    /// `Command.enabled_by`: whether one of the given enabled services enables it.
    func isEnabled(by enabledServices: [String]) -> Bool {
        services.contains { enabledServices.contains($0) }
    }
}

/// Commands enabled by the vehicle's enabled services (`supported_commands`).
nonisolated func supportedCommands(services: [String]) -> Set<JeepCommand> {
    Set(JeepCommand.allCases.filter { $0.isEnabled(by: services) })
}

/// Names of services that are both `vehicleCapable` and `serviceEnabled`
/// (`apply_list_item` in `models.py`). `items` is the decoded `services` array.
nonisolated func enabledServices(_ items: Any?) -> [String] {
    guard let list = items as? [Any] else { return [] }
    return list.compactMap { item -> String? in
        guard let dict = item as? [String: Any],
              let name = dict["service"] as? String,
              jsonBool(dict["vehicleCapable"]) == true,
              jsonBool(dict["serviceEnabled"]) == true
        else { return nil }
        return name
    }
}

/// `enabledServices` for a raw JSON array such as `services.json`.
nonisolated func enabledServices(fromJSON data: Data) -> [String] {
    enabledServices(try? JSONSerialization.jsonObject(with: data))
}

/// `get_bool` in `models.py`: a JSON boolean, or the strings "true"/"false" in any case.
/// Numbers are not booleans (JSONSerialization would otherwise bridge 1 to true).
nonisolated func jsonBool(_ value: Any?) -> Bool? {
    if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue
    }
    if let string = value as? String {
        switch string.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
    return nil
}
