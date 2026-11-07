import SwiftUI
import os

private let sceneLog = Logger(subsystem: "com.milanpatel.Forx", category: "scene")

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
                reopenCarPlayScene()
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

    /// Demo builds only (`FORX_CP=demo…`): after a relaunch, asks UIKit to bring the CarPlay scene
    /// back up, so the simulator's CarPlay screen shows Forx again without a tap on its icon.
    /// Logs what UIKit says (subsystem com.milanpatel.Forx, category scene).
    private func reopenCarPlayScene() {
        #if DEBUG
        guard CarPlayDebug.demo else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            let app = UIApplication.shared
            let roles = app.openSessions.map(\.role.rawValue)
            sceneLog.notice("open sessions: \(roles.joined(separator: ", "))")
            guard let car = app.openSessions.first(where: { $0.role == .carTemplateApplication }) else {
                sceneLog.notice("no CarPlay session to reopen")
                return
            }
            app.requestSceneSessionActivation(car, userActivity: nil, options: nil) { error in
                sceneLog.error("CarPlay scene activation failed: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
