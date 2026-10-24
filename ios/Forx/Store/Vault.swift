import Foundation
import LocalAuthentication
import Security

/// The Uconnect sign-in and the current session, kept in the Keychain as generic-password
/// items under service `com.milanpatel.Forx`. Readable after the first unlock so the
/// background refresh can use them. Nothing here is ever logged.
nonisolated struct Vault: Sendable {
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

    func clear() {
        for account in Account.allCases { SecItemDelete(query(account) as CFDictionary) }
    }

    // MARK: Keychain

    private func query(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private func write(_ data: Data, _ account: Account) throws {
        SecItemDelete(query(account) as CFDictionary)
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
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

/// Asks the owner to confirm before a sensitive command (Unlock on the iPhone).
nonisolated protocol FaceIDGate: Sendable {
    func confirm(reason: String) async -> Bool
}

/// Face ID, falling back to the device passcode (`.deviceOwnerAuthentication`).
nonisolated struct LAFaceIDGate: FaceIDGate {
    init() {}

    func confirm(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }
}
