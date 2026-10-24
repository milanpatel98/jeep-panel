import SwiftUI

/// The one sheet RootView shows at a time. Sign-in wins, so signing out from Settings
/// swaps the Settings sheet for the sign-in one.
nonisolated enum RootSheet: String, Identifiable, Equatable {
    case signIn, settings
    var id: String { rawValue }
}

nonisolated func rootSheet(needsSignIn: Bool, settingsOpen: Bool) -> RootSheet? {
    needsSignIn ? .signIn : settingsOpen ? .settings : nil
}

struct RootView: View {
    let store: JeepStore
    @State private var settingsOpen = false

    private var sheet: Binding<RootSheet?> {
        Binding(
            get: { rootSheet(needsSignIn: store.needsSignIn, settingsOpen: settingsOpen) },
            set: { if $0 == nil { settingsOpen = false } })  // swiped away; sign-in can't be
    }

    var body: some View {
        PanelWebView(store: store, onSettings: { settingsOpen = true })
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .sheet(item: sheet) { which in
                switch which {
                case .signIn: SignInView(store: store)
                case .settings: SettingsView(store: store)
                }
            }
            .onChange(of: store.needsSignIn) { _, needs in
                if needs { settingsOpen = false }
            }
    }
}
