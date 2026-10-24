import SwiftUI

/// Opened by the panel's settings button. Units stay mi / psi / °F (no units setting).
struct SettingsView: View {
    let store: JeepStore

    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: store.email ?? "—")
                }

                Section("Alerts") {
                    ForEach(Alert.allCases, id: \.self) { alert in
                        AlertToggle(alert: alert)
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        confirmSignOut = true
                    }
                    .confirmationDialog(
                        "Sign out of Uconnect?", isPresented: $confirmSignOut, titleVisibility: .visible
                    ) {
                        Button("Sign out", role: .destructive) {
                            AlertTracker(defaults: .standard).reset()
                            store.signOut()  // RootView swaps this sheet for the sign-in one
                        }
                    } message: {
                        Text("Your sign-in and PIN are removed from this iPhone.")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    static func label(_ alert: Alert) -> String {
        switch alert {
        case .leftUnlocked: "Left unlocked"
        case .lowTire: "Low tire pressure"
        case .lowRange: "Low range"
        case .chargingDone: "Charging done"
        }
    }
}

/// One alert's switch, stored in UserDefaults `alerts.<rawValue>` (on by default).
private struct AlertToggle: View {
    let alert: Alert
    @AppStorage private var on: Bool

    init(alert: Alert) {
        self.alert = alert
        _on = AppStorage(wrappedValue: true, AlertSettings.key(alert))
    }

    var body: some View {
        Toggle(SettingsView.label(alert), isOn: $on)
    }
}
