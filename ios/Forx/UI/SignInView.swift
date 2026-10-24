import SwiftUI

// MARK: - Form rules (pure, tested)

/// "Sign in" is enabled for an email with an @ and a dot, any password, and a 4-digit PIN.
nonisolated func signInIsValid(email: String, password: String, pin: String) -> Bool {
    let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let at = e.firstIndex(of: "@"), at != e.startIndex,
          e[e.index(after: at)...].contains(".") else { return false }
    return !password.isEmpty && pin.count == 4 && pin.allSatisfy(isASCIIDigit)
}

/// What the PIN field keeps of what was typed or pasted: the first 4 ASCII digits.
nonisolated func pinInput(_ text: String) -> String {
    String(text.filter(isASCIIDigit).prefix(4))
}

private nonisolated func isASCIIDigit(_ c: Character) -> Bool {
    c.isASCII && c.isNumber
}

/// The error line under the form.
nonisolated func signInMessage(for error: UconnectError) -> String {
    switch error {
    case .badLogin: "Email or password is wrong."
    case .loginRejected: "Uconnect turned down the sign-in. Try again later."
    case .badPin: "PIN is wrong."
    case .network, .timeout: "No connection. Try again."
    default: "Couldn't sign in. Try again."
    }
}

// MARK: - View

/// Shown as a sheet while the store needs a sign-in. Values stay in memory and the
/// Keychain only; nothing here is logged.
struct SignInView: View {
    let store: JeepStore

    private enum Field { case email, password, pin }

    @State private var email = ""
    @State private var password = ""
    @State private var pin = ""
    @State private var busy = false
    @State private var error: String? = nil
    @FocusState private var focus: Field?

    private var canSubmit: Bool {
        !busy && signInIsValid(email: email, password: password, pin: pin)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focus = .pin }
                } header: {
                    Text("Uconnect account")
                }

                Section {
                    SecureField("Uconnect PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .pin)
                        .onChange(of: pin) { _, new in
                            let kept = pinInput(new)
                            if kept != new { pin = kept }
                        }
                } footer: {
                    Text("The 4-digit PIN for remote commands.")
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Text("Sign in")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .disabled(busy)
            .navigationTitle("Sign in")
            .onAppear { if email.isEmpty { focus = .email } }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func submit() async {
        guard canSubmit else { return }
        busy = true
        error = nil
        focus = nil
        do throws(UconnectError) {
            try await store.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, pin: pin)
            password = ""
            pin = ""
            await Refresher.requestNotificationPermission()
        } catch {
            self.error = signInMessage(for: error)
        }
        busy = false
    }
}
