import Foundation
import Observation

// MARK: - Seams (fakes in tests)

/// What the store needs from `UconnectAPI`.
nonisolated protocol UconnectAPIProtocol: Sendable {
    func vehicles() async throws(UconnectError) -> [VehicleSummary]
    func info(vin: String) async throws(UconnectError) -> Data
    func remoteStatus(vin: String) async throws(UconnectError) -> Data
    func location(vin: String) async throws(UconnectError) -> Data
    func send(_ cmd: JeepCommand, vin: String, pin: String) async throws(UconnectError)
    func update(session: Session) async
}

/// What the store needs from `UconnectAuth`.
nonisolated protocol UconnectAuthProtocol: Sendable {
    func login(email: String, password: String) async throws(UconnectError) -> Session
}

/// What the store needs from `Vault`.
nonisolated protocol VaultProtocol: Sendable {
    func save(email: String, password: String, pin: String) throws
    func load() -> (email: String, password: String, pin: String)?
    func saveSession(_ session: Session)
    func loadSession() -> Session?
    func clear()
}

// MARK: - Store

/// The one observable state of the app: the iPhone panel and CarPlay both read it.
/// Nothing here is logged: credentials, PIN, session, VIN and location are secrets.
@Observable
final class JeepStore {
    static let noAnswer = "Jeep didn't answer. Try again."
    static let unlockReason = "Unlock your Jeep"
    /// The UI gives up on a command after this long, even if the network call is still polling.
    static let commandDeadline: Duration = .seconds(60)
    static let messageDuration: Duration = .seconds(4)
    /// Log in again this long before the session expires (a minute ahead of the API's own margin).
    static let reloginMargin: TimeInterval = UconnectAPI.sessionMargin + 60

    private(set) var snapshot: JeepSnapshot? = nil
    private(set) var pending: Set<JeepCommand> = []
    private(set) var offline = false
    private(set) var message: String? = nil
    /// Bumped for every new message, even the same text, so the panel shows it again.
    private(set) var messageId = 0
    private(set) var needsSignIn: Bool
    private(set) var vin: String? = nil

    /// Called with the snapshot shown before and the new one, each time a refresh reads the Jeep
    /// (foreground or background). The alert tracker learns from it.
    @ObservationIgnored var onSnapshot: ((_ previous: JeepSnapshot?, _ current: JeepSnapshot) -> Void)? = nil

    @ObservationIgnored private let makeAPI: (Session) -> any UconnectAPIProtocol
    @ObservationIgnored private let auth: any UconnectAuthProtocol
    @ObservationIgnored private let vault: any VaultProtocol
    @ObservationIgnored private let faceID: any FaceIDGate
    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var api: (any UconnectAPIProtocol)? = nil
    @ObservationIgnored private var sessionExpiresAt: Date? = nil
    @ObservationIgnored private var services: [String] = []
    /// Bumped on sign-in and sign-out so late results of the old account are dropped.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>? = nil
    @ObservationIgnored private var reloginTask: Task<Bool, Never>? = nil
    /// The attempt that currently owns each pending command, and its 60 s deadline.
    @ObservationIgnored private var attempts: [JeepCommand: Int] = [:]
    @ObservationIgnored private var deadlines: [JeepCommand: Task<Void, Never>] = [:]
    /// Attempts the Jeep confirmed; they stay pending only while the follow-up refresh runs.
    @ObservationIgnored private var confirmed: Set<Int> = []
    @ObservationIgnored private var attemptSerial = 0

    init(
        makeAPI: @escaping (Session) -> any UconnectAPIProtocol,
        auth: any UconnectAuthProtocol,
        vault: any VaultProtocol,
        faceID: any FaceIDGate,
        cache: SnapshotCache,
        now: @escaping () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.makeAPI = makeAPI
        self.auth = auth
        self.vault = vault
        self.faceID = faceID
        self.cache = cache
        self.now = now
        self.sleep = sleep
        let signedIn = vault.load() != nil
        needsSignIn = !signedIn
        if signedIn, let session = vault.loadSession() {
            api = makeAPI(session)
            sessionExpiresAt = session.expiresAt
        }
    }

    /// What is shown, or else the snapshot on disk: the background refresh compares the
    /// next reading with this.
    var lastKnownSnapshot: JeepSnapshot? {
        snapshot ?? cache.load()
    }

    /// The signed-in Uconnect email, for Settings. Read from the Keychain; never logged.
    var email: String? {
        vault.load()?.email
    }

    /// The patch for `window.jeepNative.apply(patch)`.
    var patch: [String: Any] {
        panelPatch(snapshot, pending: pending, offline: offline, message: message, messageId: messageId, now: now())
    }

    // MARK: Sign-in

    /// Logs in, keeps the sign-in and PIN in the Keychain, then reads the Jeep.
    /// A wrong email or password throws `.badLogin` and saves nothing.
    func signIn(email: String, password: String, pin: String) async throws(UconnectError) {
        let session = try await auth.login(email: email, password: password)
        do {
            try vault.save(email: email, password: password, pin: pin)
        } catch {
            throw UconnectError.unexpected("Keychain write failed")
        }
        vault.saveSession(session)
        epoch += 1
        api = makeAPI(session)
        sessionExpiresAt = session.expiresAt
        vin = nil
        services = []
        offline = false
        needsSignIn = false
        await refresh(fresh: true)
    }

    /// Forgets the account: Keychain items, the cached snapshot and all state.
    func signOut() {
        epoch += 1
        vault.clear()
        try? FileManager.default.removeItem(at: cache.url)
        for task in deadlines.values { task.cancel() }
        deadlines = [:]
        attempts = [:]
        confirmed = []
        api = nil
        sessionExpiresAt = nil
        vin = nil
        services = []
        snapshot = nil
        pending = []
        offline = false
        message = nil
        needsSignIn = true
    }

    // MARK: Refresh

    /// Reads the Jeep. Shows the cached snapshot first; marks `offline` when the network is down.
    /// Joins a refresh that is already running instead of starting a second one.
    func refresh() async {
        await refresh(fresh: false)
    }

    /// `fresh`: the caller needs data read after this call (after a command), so a refresh
    /// already running is awaited and then a new one runs.
    private func refresh(fresh: Bool) async {
        if let running = refreshTask {
            await running.value
            guard fresh else { return }
            if let next = refreshTask {  // another caller started one after ours was needed
                await next.value
                return
            }
        }
        let task = Task {
            await self.runRefresh()
            self.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func runRefresh() async {
        let epoch = self.epoch
        if snapshot == nil, let cached = cache.load() {
            snapshot = cached
        }
        guard !needsSignIn else { return }

        // At most one login per refresh.
        var loggedIn = false
        if api == nil || sessionNearExpiry {
            guard await relogin() else { return }
            loggedIn = true
        }
        guard epoch == self.epoch, let firstAPI = api else { return }

        var result = await fetch(firstAPI, epoch: epoch)
        if case .failure(.sessionExpired) = result, !loggedIn {
            guard await relogin(), epoch == self.epoch, let retryAPI = api else { return }
            result = await fetch(retryAPI, epoch: epoch)
        }
        guard epoch == self.epoch else { return }

        switch result {
        case .success(let s):
            let previous = snapshot
            snapshot = s
            offline = false
            try? cache.save(s)
            onSnapshot?(previous, s)
        case .failure(.network):
            offline = true
        case .failure:
            break  // keep what is shown; its age says how old it is
        }
    }

    private func fetch(_ api: any UconnectAPIProtocol, epoch: Int) async -> Result<JeepSnapshot, UconnectError> {
        do throws(UconnectError) {
            if vin == nil {
                // Milan's account has one vehicle: use the first.
                guard let first = try await api.vehicles().first else {
                    throw UconnectError.unexpected("no vehicle on the account")
                }
                guard epoch == self.epoch else { throw UconnectError.unexpected("signed out") }
                vin = first.vin
                services = first.services
            }
            guard let vin else { throw UconnectError.unexpected("no vehicle") }

            let info = try await api.info(vin: vin)
            // Remote status and location are optional: only an expired session stops the refresh.
            var status: Data?
            do throws(UconnectError) {
                status = try await api.remoteStatus(vin: vin)
            } catch {
                if error == .sessionExpired { throw error }
            }
            var location: Data?
            do throws(UconnectError) {
                location = try await api.location(vin: vin)
            } catch {
                if error == .sessionExpired { throw error }
            }

            guard let s = try? JeepSnapshot.parse(
                info: info, status: status, location: location, services: services, now: now())
            else { throw UconnectError.unexpected("status could not be read") }
            return .success(s)
        } catch {
            return .failure(error)
        }
    }

    private var sessionNearExpiry: Bool {
        guard let sessionExpiresAt else { return true }
        return now() >= sessionExpiresAt.addingTimeInterval(-Self.reloginMargin)
    }

    /// Logs in again from the Vault; joins a login already running. A wrong password
    /// sets `needsSignIn` and no further login is tried until the owner signs in
    /// (Gigya locks accounts that retry).
    private func relogin() async -> Bool {
        if let running = reloginTask {
            return await running.value
        }
        let task = Task {
            let ok = await self.runRelogin()
            self.reloginTask = nil
            return ok
        }
        reloginTask = task
        return await task.value
    }

    private func runRelogin() async -> Bool {
        guard !needsSignIn else { return false }
        guard let creds = vault.load() else {
            needsSignIn = true
            return false
        }
        let epoch = self.epoch
        let session: Session
        do throws(UconnectError) {
            session = try await auth.login(email: creds.email, password: creds.password)
        } catch {
            guard epoch == self.epoch else { return false }
            switch error {
            case .badLogin: needsSignIn = true
            case .network: offline = true
            default: break
            }
            return false
        }
        guard epoch == self.epoch else { return false }
        vault.saveSession(session)
        sessionExpiresAt = session.expiresAt
        if let api {
            await api.update(session: session)
        } else {
            api = makeAPI(session)
        }
        return true
    }

    // MARK: Commands

    /// Sends a command. The control shows pending until the Jeep confirms and a refresh
    /// shows the new state. A failure, or no answer within 60 s, reverts it with
    /// "Jeep didn't answer. Try again." A command is never sent again automatically.
    func perform(_ cmd: JeepCommand, fromCarPlay: Bool = false) async {
        guard !pending.contains(cmd), !needsSignIn else { return }
        if cmd == .unlock && !fromCarPlay {
            guard await faceID.confirm(reason: Self.unlockReason) else { return }
            guard !pending.contains(cmd), !needsSignIn else { return }
        }

        let attempt = begin(cmd)
        if api == nil || vin == nil {
            await refresh(fresh: true)
        }
        if !needsSignIn && sessionNearExpiry {
            _ = await relogin()  // before sending, so nothing is ever re-sent
        }
        guard attempts[cmd] == attempt else { return }  // deadline passed or signed out meanwhile
        guard !needsSignIn, let api, let vin, let pin = vault.load()?.pin else {
            fail(cmd, attempt)
            return
        }

        var failure: UconnectError?
        do throws(UconnectError) {
            try await api.send(cmd, vin: vin, pin: pin)
        } catch {
            failure = error
        }

        if let failure {
            fail(cmd, attempt)
            if failure == .sessionExpired {
                // The car may already have acted: don't resend. Log in again for the next call.
                _ = await relogin()
            }
            return
        }

        // Success. If the deadline already reverted the control, the result is only
        // picked up by this refresh; otherwise the control stays pending until it's done
        // (and if the deadline passes during it, it just ends without the failure copy).
        confirmed.insert(attempt)
        await refresh(fresh: true)
        end(cmd, attempt)
        confirmed.remove(attempt)
    }

    private func begin(_ cmd: JeepCommand) -> Int {
        attemptSerial += 1
        let attempt = attemptSerial
        attempts[cmd] = attempt
        pending.insert(cmd)
        let sleep = self.sleep
        deadlines[cmd]?.cancel()
        deadlines[cmd] = Task { [weak self] in
            do {
                try await sleep(Self.commandDeadline)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            if self.confirmed.contains(attempt) {
                self.end(cmd, attempt)
            } else {
                self.fail(cmd, attempt)
            }
        }
        return attempt
    }

    /// Reverts the command and shows the failure copy, if `attempt` still owns it.
    private func fail(_ cmd: JeepCommand, _ attempt: Int) {
        guard attempts[cmd] == attempt else { return }
        end(cmd, attempt)
        show(Self.noAnswer)
    }

    private func end(_ cmd: JeepCommand, _ attempt: Int) {
        guard attempts[cmd] == attempt else { return }
        attempts[cmd] = nil
        pending.remove(cmd)
        deadlines.removeValue(forKey: cmd)?.cancel()
    }

    private func show(_ text: String) {
        messageId += 1
        message = text
        let id = messageId
        let sleep = self.sleep
        Task { [weak self] in
            do {
                try await sleep(Self.messageDuration)
            } catch {
                return
            }
            guard let self, self.messageId == id else { return }
            self.message = nil
        }
    }
}
