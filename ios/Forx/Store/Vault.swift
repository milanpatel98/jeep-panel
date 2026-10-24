import Foundation
import LocalAuthentication
import Security

/// The Uconnect sign-in and the current session, kept in the Keychain as generic-password
/// items under service `com.milanpatel.Forx`. Readable after the first unlock so the
/// background refresh can use them. Nothing here is ever logged.
nonisolated struct Vault: Sendable, VaultProtocol {
    nonisolated enum VaultError: Error, Equatable {
        case keychain(OSStatus)
        case encoding
    }

    static let service = "com.milanpatel.Forx"

    nonisolated private enum Account: String, CaseIterable {
        case email, password, pin, session
    }

    init() {}

    func save(email: String, password: String, pin: String) throws {
        try write(Data(email.utf8), .email)
        try write(Data(password.utf8), .password)
        try write(Data(pin.utf8), .pin)
    }

    func load() -> (email: String, password: String, pin: String)? {
        guard let email = string(.email), let password = string(.password), let pin = string(.pin)
        else { return nil }
        return (email, password, pin)
    }

    /// Best effort: a session that fails to save only means a fresh login next time.
    func saveSession(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? write(data, .session)
    }

    func loadSession() -> Session? {
        read(.session).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    /// Drops the PIN only: `load()` returns nil until the next sign-in saves a new one.
    func forgetPin() {
        _ = SecItemDelete(query(.pin) as CFDictionary)
    }

    func clear() {
        for account in Account.allCases { _ = SecItemDelete(query(account) as CFDictionary) }
    }

    // MARK: Keychain

    private func query(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    /// Update in place, adding only when the item doesn't exist yet, so a failed write
    /// never loses the old value.
    private func write(_ data: Data, _ account: Account) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    private func read(_ account: Account) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func string(_ account: Account) -> String? {
        read(account).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// What the owner answered to the Face ID prompt.
nonisolated enum FaceIDAnswer: Sendable, Equatable {
    case confirmed
    case declined
    /// The phone has no Face ID, Touch ID or passcode set up: there is nothing to ask.
    case unavailable
}

/// Asks the owner to confirm before a sensitive command (Unlock and Tailgate on the iPhone).
nonisolated protocol FaceIDGate: Sendable {
    func confirm(reason: String) async -> FaceIDAnswer
}

/// Face ID, falling back to the device passcode (`.deviceOwnerAuthentication`).
nonisolated struct LAFaceIDGate: FaceIDGate {
    init() {}

    func confirm(reason: String) async -> FaceIDAnswer {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        let ok = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
        withExtendedLifetime(context) {}  // keep the context alive until the prompt is answered
        return ok ? .confirmed : .declined
    }
}
