import SwiftUI

@main
struct ForxApp: App {
    /// Refresh this often while the app is open.
    static let foregroundInterval: Duration = .seconds(120)

    @Environment(\.scenePhase) private var scenePhase
    @State private var store: JeepStore
    @State private var foregroundRefresh: Task<Void, Never>? = nil

    init() {
        let store = AppModel.store
        _store = State(initialValue: store)
        // Before the app finishes launching, as BGTaskScheduler requires.
        Refresher.register(store: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)  // the phone stays dark; CarPlay follows the car
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
}
