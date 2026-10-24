import Foundation
import Observation

/// The roof state shown on the 3D Jeep: "on", "panels" or "off". Persisted in UserDefaults "roof".
@Observable
final class RoofSetting {
    static let shared = RoofSetting()
    static let key = "roof"

    var value: String {
        didSet {
            guard Self.valid.contains(value) else { value = oldValue; return }
            UserDefaults.standard.set(value, forKey: Self.key)
        }
    }

    private static let valid: Set<String> = ["on", "panels", "off"]

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        value = saved.flatMap { Self.valid.contains($0) ? $0 : nil } ?? "on"
    }
}

/// The one store shared by the phone and CarPlay.
@MainActor
enum AppModel {
    static let store: JeepStore = makeStore()

    static var roof: String {
        get { RoofSetting.shared.value }
        set { RoofSetting.shared.value = newValue }
    }

    private static func makeStore() -> JeepStore {
        let transport = URLSessionTransport()
        let folder = URL.applicationSupportDirectory.appendingPathComponent("forx", isDirectory: true)
        return JeepStore(
            makeAPI: { UconnectAPI(transport: transport, session: $0) },
            auth: UconnectAuth(transport: transport),
            vault: Vault(),
            faceID: LAFaceIDGate(),
            cache: SnapshotCache(url: folder.appendingPathComponent("snapshot.json")),
            now: { Date() })
    }
}
