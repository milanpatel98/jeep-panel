import SwiftUI

@main
struct ForxApp: App {
    /// Refresh this often while the app is open.
    static let foregroundInterval: Duration = .seconds(120)

    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ForxApp.makeStore()
    @State private var foregroundRefresh: Task<Void, Never>? = nil

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                startForegroundRefresh()
            case .background:
                stopForegroundRefresh()
                scheduleBackgroundRefresh()
            default:
                stopForegroundRefresh()
            }
        }
    }

    /// Refreshes now, then every 120 s until the app leaves the foreground.
    private func startForegroundRefresh() {
        foregroundRefresh?.cancel()
        let store = self.store
        foregroundRefresh = Task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: Self.foregroundInterval)
            }
        }
    }

    private func stopForegroundRefresh() {
        foregroundRefresh?.cancel()
        foregroundRefresh = nil
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
