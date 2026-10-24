# Jeep iPhone App Implementation Plan (sub-project 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Jeep Panel into a native iPhone app that shows Milan's real Jeep from Uconnect and sends real commands under the spec's rules.

**Architecture:**
- A SwiftUI app hosts the existing Jeep Panel web app (built with Vite into the app bundle) in a WKWebView.
- Swift owns everything real: the Uconnect client, the Keychain, Face ID, the refresh timer, background refresh and alerts.
- The web side only renders state and asks for commands over a small JSON bridge.

**Tech Stack:**
- iOS: iOS 26, Swift 6, SwiftUI, WebKit, LocalAuthentication, Security, BackgroundTasks, UserNotifications, CryptoKit, Swift Testing, XcodeGen.
- Web: Vite 5, three.js 0.169, node:test.

**Spec:** `docs/superpowers/specs/2026-10-24-jeep-carplay-design.md` (this plan covers §3 iPhone, §4, §5 minus CarPlayUI and GlobeView, and §6; CarPlay and the Apps tray are plans 2 and 3).

**Reference implementation:** py-uconnect (Apache-2.0) at `/tmp/claude-0/-home-claude/49428304-0dd0-528c-984a-fb334289ec08/scratchpad/uconnect/py-uconnect/py_uconnect/`.
- Port its behaviour and read its files for exact URLs, headers and JSON paths: `auth.py`, `sigv4.py`, `api.py`, `command.py`, `models.py`, `brands.py` (`JEEP_US`), `_http.py`.
- Credit it in `ios/README.md`.

## Global Constraints

- Platform: iOS 26.0 deployment target, Swift 6.0 language mode.
  - Build settings: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- Dependencies: no third-party Swift packages. Apple frameworks only.
- Project:
  - XcodeGen `ios/project.yml` is the source of truth; the `.xcodeproj` is never committed.
  - Bundle id `com.milanpatel.Forx`; app name "Forx".
- Signing: free Apple account. No CarPlay or other restricted entitlement in this plan.
- Secrets:
  - No password, PIN, token, VIN or GPS coordinate in any committed file, test fixture or log line.
  - Fixtures use VIN `1C4JJXP60RW000000` and location `0.0, 0.0`.
  - `Logger` interpolations of secrets use `privacy: .private`, or are not logged at all.
- Rules from the spec:
  - Every control starts off and turns on only after the Jeep confirms.
  - Unlock on iPhone requires Face ID; Lock does not.
  - Commands time out after 60 s and revert with the copy `Jeep didn't answer. Try again.`
- Units: mi, psi, °F (km → mi ×0.621371, kPa → psi ×0.145038, °C → °F ×9/5+32), rounded to whole numbers for display.
- Refresh:
  - every 120 s while the app is in the foreground, plus pull-to-refresh;
  - background via `BGAppRefreshTask` id `com.milanpatel.Forx.refresh`.
- Alerts:
  - unlocked ≥ 10 min while parked;
  - any tire < 32 psi;
  - range < 40 mi;
  - charging went from charging to full/complete.
- Commits:
  - author and committer `Milan Patel <82750336+milanpatel98@users.noreply.github.com>`;
  - no Co-Authored-By or any Claude/AI line;
  - use `git -c user.name="Milan Patel" -c user.email="82750336+milanpatel98@users.noreply.github.com" commit …`.
- Swift tests: no Swift compiler exists in the cloud workspace.
  - Implementers write tests first and code against them; reviewers check them by reading.
  - Tests are run on Milan's Mac at the three **Mac checkpoints** (Tasks 6, 10, 13) with `xcodebuild test`, or ⌘U in Xcode.
  - A task is only "verified" after its checkpoint passes.
- Web tests: run here with `node --test web-tests/`.
- Footer/credits: keep the existing Jeep Panel footer "© 2026 Milan Patel · MIT License".

## Review Focus

1. **Password changed or account locked:**
   - silent re-login fails → the app shows the sign-in sheet once and stops retrying;
   - it must never loop logins (Gigya locks the account).
   - Test: `JeepStoreTests.reloginFailureStopsAndAsks`, Task 9.
2. **Command status never resolves, or resolves FAILURE:**
   - the button reverts at 60 s or on FAILURE with the spec copy;
   - nothing is left spinning.
   - Tests: `UconnectAPITests.pollTimesOutAt60s`, Task 5; `JeepStoreTests.failureReverts`, Task 9.
3. **Double tap while a command is pending:**
   - the second tap is ignored; one request is sent.
   - Test: `JeepStoreTests.secondTapWhilePendingIsIgnored`, Task 9.
4. **Partial or null JSON from Uconnect** (windows/hvac/liftgate null, a missing tire):
   - those fields are nil and hidden; no crash; other values still show.
   - Test: `SnapshotTests.nullFieldsStayNil`, Task 7.
5. **Launch with no network or with the phone just unlocked:**
   - the last snapshot loads from disk (file protection `completeUntilFirstUserAuthentication`) and is marked offline.
   - Test: `SnapshotCacheTests.loadsLastSnapshotOffline`, Task 9.

---

## File Structure

```
package.json                      # add "build:app" and "test:web" scripts
vite.app.config.js                # base './', outDir ios/Forx/Web, emptyOutDir true
src/native.js                     # bridge: detects WKWebView, routes commands to Swift, applies Swift patches
src/state.js                      # modify: real-data defaults when native (all off, unknown values null)
src/main.js                       # modify: route Lock/Climate/Lights/Horn/Gate actions through native.request()
src/style.css                     # modify: .pending spinner ring, .hidden for unsupported controls
web-tests/native.test.js
web-tests/state.test.js
ios/
  project.yml
  README.md                       # Mac commands, credits (py-uconnect Apache-2.0, three.js MIT, Phosphor MIT)
  Forx/
    App.swift                     # @main, scenePhase timer, BG task registration
    Info.plist                    # generated by XcodeGen from project.yml
    Uconnect/HTTPTransport.swift  # protocol + URLSession impl (the seam tests stub)
    Uconnect/SigV4.swift
    Uconnect/UconnectAuth.swift
    Uconnect/UconnectAPI.swift
    Uconnect/Commands.swift       # command table + supportedCommands(services:)
    Model/JeepSnapshot.swift      # parsed, unit-converted state
    Model/PanelPatch.swift        # JeepSnapshot → JSON patch for src/state.js
    Model/AlertRules.swift
    Store/Vault.swift             # Keychain + FaceIDGate
    Store/SnapshotCache.swift
    Store/JeepStore.swift
    UI/PanelWebView.swift         # WKWebView + forx:// scheme handler + message bridge
    UI/SignInView.swift
    UI/SettingsView.swift
    UI/RootView.swift
    Background/Refresher.swift    # BGAppRefreshTask + notifications
    Web/                          # Vite output, committed (built by `npm run build:app`)
  ForxTests/
    Fixtures/*.json               # generated by tools/make_fixtures.py, no real data
    SigV4Tests.swift  UconnectAuthTests.swift  UconnectAPITests.swift  CommandsTests.swift
    SnapshotTests.swift  PanelPatchTests.swift  AlertRulesTests.swift  SnapshotCacheTests.swift  JeepStoreTests.swift
    StubTransport.swift
tools/make_fixtures.py            # runs py-uconnect's pure functions to produce expected values
```

---

### Task 1: Xcode project skeleton

**Files:**
- Create: `ios/project.yml`, `ios/Forx/App.swift`, `ios/Forx/UI/RootView.swift`, `ios/ForxTests/SmokeTests.swift`, `ios/README.md`, `ios/.gitignore`

**Interfaces:**
- Produces: target `Forx`, test target `ForxTests`, scheme `Forx`, folder `ios/Forx/Web` as a folder reference (copied as `Web/` in the bundle).

- [ ] **Step 1: Write `SmokeTests.swift`** with `@Test func appBundleHasWebFolder()` asserting `Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") != nil`.
- [ ] **Step 2: Write `project.yml`.**
  - Start from the xcode-handoff skill template: name `Forx`, bundleIdPrefix `com.milanpatel`, iOS 26.0, `SWIFT_VERSION 6.0`.
  - Add the two concurrency settings from Global Constraints.
  - Info properties: `CFBundleDisplayName: Jeep`, `UILaunchScreen: {}`, `UIBackgroundModes: [fetch]`, `BGTaskSchedulerPermittedIdentifiers: [com.milanpatel.Forx.refresh]`, `NSFaceIDUsageDescription: "Face ID confirms it's you before unlocking the Jeep."`, `UIUserInterfaceStyle: Dark`.
  - Sources: `Forx` with `Web` as `type: folder`.
  - No entitlements file.
- [ ] **Step 3: Write `App.swift` and `RootView.swift`:** a black full-screen view. Write `ios/README.md` with the 3 Mac commands from the xcode-handoff skill (`cd ~/Developer/jeep-panel/ios && git pull && xcodegen && open Forx.xcodeproj`) and the credits. Write `.gitignore`: `*.xcodeproj`, `DerivedData/`, `build/`, `xcuserdata/`.
- [ ] **Step 4: Put a placeholder `ios/Forx/Web/index.html`** (Task 3 replaces it).
- [ ] **Step 5: Commit** `ios/` with message `iOS app skeleton`.

### Task 2: Fixture generator

**Files:**
- Create: `tools/make_fixtures.py`, `ios/ForxTests/Fixtures/` (output)

**Interfaces:**
- Produces fixture files read by later tests through `Fixture.data("name")` (defined in Task 4's `StubTransport.swift`):
  - `sigv4_get.json`: `{request:{method,url,headers,body}, creds:{access,secret,session}, now:"2026-10-24T12:00:00Z", region:"us-east-1", expected:{authorization, x_amz_date}}`.
  - `vehicles.json`: the list-vehicles response shape.
  - `vehicle_info.json`: info with tires in kPa, odometer in km, range in km, EV block, `windows/hvac/liftgate` null, one tire missing.
  - `remote_status.json`: doors all locked.
  - `pin_ok.json`: `{"token":"pin-token","expiry":300000}`.
  - `command_ok.json`: `{"correlationId":"corr-1"}`.
  - `status_pending.json`, `status_success.json`, `status_failure.json`: last-status responses with `status` `PENDING`/`SUCCESS`/`FAILURE`.
  - `services.json`: list of enabled services enabling RDL, RDU, HBLF, REON.

- [ ] **Step 1: Write `tools/make_fixtures.py`.**
  - Import py-uconnect from the reference path with `sys.path.insert`.
  - Compute the SigV4 expected values by calling its `sigv4` signer on a fixed request.
  - Hand-write the JSON shapes, following the paths read in `models.py` (`apply_list_item`, `apply_vehicle_info`, `apply_remote_status`, `parse_location`), using the fake VIN and 0,0 location.
- [ ] **Step 2: Run** `python3 -I tools/make_fixtures.py ios/ForxTests/Fixtures`. Expected: the files above exist. `grep -rE "RW[0-9]{6}" ios/ForxTests/Fixtures` shows only `RW000000`.
- [ ] **Step 3: Commit** with message `Fixtures for the Uconnect client`.

### Task 3: Web bridge in Jeep Panel

**Files:**
- Create: `src/native.js`, `vite.app.config.js`, `web-tests/native.test.js`, `web-tests/state.test.js`
- Modify: `src/state.js`, `src/main.js`, `src/style.css`, `package.json`, `index.html` (load `native.js` before `main.js`)

**Interfaces:**
- Produces (JS, the contract Task 11's Swift side must match):
  - `isNative(): boolean`. True when `window.webkit?.messageHandlers?.jeep` exists.
  - `request(action)`: posts `{type:"command", action}` to `window.webkit.messageHandlers.jeep`.
    - `action` is one of `"lock"|"unlock"|"climateOn"|"climateOff"|"lights"|"horn"|"gate"`.
    - In the browser (not native), it falls back to the existing local `set()` toggles.
  - `window.jeepNative.apply(patch)`: calls `set(patch)`.
    - Patch keys are the existing `state` keys plus:
      - `pending: {lock?:bool, climate?:bool, lights?:bool, horn?:bool, gate?:bool}`;
      - `supported: string[]` (subset of `["lock","climate","lights","horn","gate"]`);
      - `updated: string` (e.g. "Updated 3 min ago");
      - `offline: boolean`;
      - `message: string|null`.
  - On load in native mode, posts `{type:"ready"}`.
- Defaults when native:
  - `name:"Milan"`, `locked:null`, `lights:false`, `climate.on:false`;
  - battery, fuel and odometer `null`;
  - `supported:[]`, so all command buttons are hidden until Swift sends the list.
  - Browser mode keeps today's sample data unchanged.

- [ ] **Step 1: Write failing tests.**
  - `web-tests/state.test.js`:
    - `nativeDefaultsAreOff`: with a fake `globalThis.window.webkit.messageHandlers.jeep`, importing `state.js` gives `locked === null`, `lights === false`, `climate.on === false`, `name === "Milan"`.
    - `browserDefaultsUnchanged`.
  - `web-tests/native.test.js`:
    - `requestPostsCommand`: the posted message equals `{type:"command", action:"lock"}`.
    - `applyPatchesState`: `apply({pending:{lock:true}})` sets `state.pending.lock === true`.
    - `readyPostedOnLoad`.
- [ ] **Step 2: Run** `node --test web-tests/`. Expected: FAIL (module not found).
- [ ] **Step 3: Implement `src/native.js` and the `state.js` defaults.**
- [ ] **Step 4: Route actions in `main.js`.**
  - The quick buttons and tiles for lock, climate, lights, horn and gate call `request()`.
  - Lock picks `unlock` when `state.locked`, else `lock`.
  - Climate picks `climateOff` when `state.climate.on`.
  - In render:
    - add class `pending` to the button while `state.pending[k]`;
    - add class `hidden` when native and `k` is not in `state.supported`;
    - show `state.message` in the existing status line for 4 s;
    - show `state.updated` under the status;
    - dim stats with class `stale` when `offline`.
  - Null values render as `—`.
  - `style.css`: `.q.pending` gets a 2px rotating ring (transform rotate, 900 ms linear, disabled under `prefers-reduced-motion`); `.hidden{display:none}`.
- [ ] **Step 5: Run** `node --test web-tests/`. Expected: PASS. Then `npm run build` (site) still succeeds.
- [ ] **Step 6: Add the build script** `"build:app": "vite build -c vite.app.config.js"` (base `./`, outDir `ios/Forx/Web`, emptyOutDir true, publicDir `public`) and run it.
  - Expected: `ios/Forx/Web/index.html` and `model/jeep.glb` exist.
- [ ] **Step 7: Commit** with message `Jeep Panel talks to the iPhone app`.

### Task 4: Transport seam + SigV4

**Files:**
- Create: `ios/Forx/Uconnect/HTTPTransport.swift`, `ios/Forx/Uconnect/SigV4.swift`, `ios/ForxTests/StubTransport.swift`, `ios/ForxTests/SigV4Tests.swift`

**Interfaces:**
- Produces:
  - `protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`;
  - `struct URLSessionTransport: HTTPTransport`;
  - `struct AWSCredentials: Sendable, Codable { accessKeyId, secretAccessKey, sessionToken: String }`;
  - `enum SigV4 { static func sign(_ request: inout URLRequest, credentials: AWSCredentials, region: String, service: String = "execute-api", now: Date) }`.
- Test helpers:
  - `final class StubTransport: HTTPTransport`: queue of `(match: (URLRequest)->Bool, status: Int, body: Data)`, records `sent: [URLRequest]`.
  - `enum Fixture { static func data(_ name: String) -> Data }`.

- [ ] **Step 1: Write `SigV4Tests.matchesPyUconnect`.** Load `sigv4_get.json`, sign, `#expect` the `Authorization` and `X-Amz-Date` headers equal `expected`.
- [ ] **Step 2: Implement `SigV4.sign`** (CryptoKit HMAC-SHA256; canonical request exactly as `sigv4.py`) and the transports.
- [ ] **Step 3: Commit** with message `SigV4 signing`.

### Task 5: Uconnect login, PIN and commands

**Files:**
- Create: `ios/Forx/Uconnect/UconnectAuth.swift`, `ios/Forx/Uconnect/UconnectAPI.swift`, `ios/Forx/Uconnect/Commands.swift`, `ios/ForxTests/UconnectAuthTests.swift`, `ios/ForxTests/UconnectAPITests.swift`, `ios/ForxTests/CommandsTests.swift`

**Interfaces:**
- Consumes: `HTTPTransport`, `SigV4`, `AWSCredentials`.
- Produces:
  - `struct Session: Codable, Sendable { uid: String; aws: AWSCredentials; expiresAt: Date }`;
  - `enum UconnectError: Error, Equatable { badLogin, badPin, network, timeout, commandFailed, unexpected(String) }`;
  - `struct UconnectAuth { init(transport:); func login(email: String, password: String) async throws(UconnectError) -> Session }`. JEEP_US brand constants come from `brands.py`.
  - `actor UconnectAPI`:
    - `init(transport:, session:, now: @Sendable () -> Date = Date.init, sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })`;
    - `func vehicles() async throws(UconnectError) -> [VehicleSummary]`;
    - `func info(vin:) async throws(UconnectError) -> Data` (raw JSON; parsed in Task 7);
    - `func remoteStatus(vin:) async throws(UconnectError) -> Data`;
    - `func location(vin:) async throws(UconnectError) -> Data`;
    - `func send(_ cmd: JeepCommand, vin: String, pin: String) async throws(UconnectError)`. Returns only after `SUCCESS`; polls `last-status` every 3 s; throws `.timeout` at 60 s and `.commandFailed` on `FAILURE`.
  - `struct VehicleSummary: Sendable { vin: String; nickname: String?; services: [String] }`.
  - `enum JeepCommand: String, CaseIterable { lock="RDL", unlock="RDU", climateOn="REON", climateOff="REOFF", lights="ROLIGHTS", horn="HBLF", gate="ROLIFTGATEUNLOCK" }`. URL suffix and api version per `command.py`, including the v2 ones.
  - `func supportedCommands(services: [String]) -> Set<JeepCommand>`, mirroring `Command.enabled_by` and the `services` tuples in `command.py`.

- [ ] **Step 1: Write failing tests.**
  - `UconnectAuthTests.loginHappyPath`: stub the 4 calls (accounts.login, accounts.getJWT, token exchange, Cognito) with fixture-shaped bodies; expect the session uid and keys.
  - `UconnectAuthTests.wrongPasswordIsBadLogin`: Gigya `errorCode` 403042 → `.badLogin`.
  - `UconnectAPITests.commandPollsUntilSuccess`: pin_ok → command_ok → pending → success.
    - Expect 4 requests.
    - The pin body is base64 of the PIN.
    - The command body has `command:"RDL"` and `pinAuth:"pin-token"`.
  - `UconnectAPITests.pollTimesOutAt60s`: `now` advances 3 s per `sleep`, always pending → `.timeout`, and no more than 21 status polls.
  - `UconnectAPITests.failureStatusThrows`: → `.commandFailed`.
  - `UconnectAPITests.badPinIsBadPin`: HTTP 401 on pin → `.badPin`.
  - `CommandsTests.servicesFixtureEnablesExpected`: `services.json` → `[.lock, .unlock, .horn, .climateOn, .climateOff]`.
- [ ] **Step 2: Implement** to the interfaces above, porting `auth.py` / `api.py`. Cache the PIN token until `expiry`, less 30 s.
- [ ] **Step 3: Commit** with message `Uconnect login, PIN and commands`.

### Task 6: Mac checkpoint A

- [ ] **Step 1: Push.** Ask Milan to run `cd ~/Developer/jeep-panel && git pull && cd ios && xcodegen && xcodebuild test -project Forx.xcodeproj -scheme Forx -destination 'platform=iOS Simulator,name=iPhone 17'` (or ⌘U).
  - If the linked Mac has computer use, Claude may press ⌘U itself after asking.
  - Expected: all tests from Tasks 1–5 pass.
- [ ] **Step 2: Fix failures** in their owning task's files. Commit each fix as `Fix: <what>`.

### Task 7: Snapshot parsing and units

**Files:**
- Create: `ios/Forx/Model/JeepSnapshot.swift`, `ios/ForxTests/SnapshotTests.swift`

**Interfaces:**
- Produces:
  - `struct JeepSnapshot: Codable, Sendable, Equatable` with fields:
    - `nickname: String?`, `locked: Bool?`, `doorsOpen: [String]`, `tailgateOpen: Bool?`;
    - `rangeMiles: Int?`, `fuelPercent: Int?`, `evPercent: Int?`, `pluggedIn: Bool?`, `charging: Bool?`, `chargeMinutesLeft: Int?`;
    - `tiresPsi: [String: Int]` (keys `FL FR RL RR`), `odometerMiles: Int?`;
    - `latitude: Double?`, `longitude: Double?`;
    - `supported: Set<JeepCommand>`, `updatedAt: Date`.
  - `static func parse(info: Data, status: Data?, location: Data?, services: [String], now: Date) throws -> JeepSnapshot`.

- [ ] **Step 1: Write failing tests.**
  - `parsesFixture`: range km→mi, kPa→psi rounded, odometer.
  - `nullFieldsStayNil`: null windows/hvac/liftgate and the missing tire are absent; others present.
  - `unknownJSONDoesNotThrow`: `{}` info → snapshot with all nil.
- [ ] **Step 2: Implement** using the JSON paths from `models.py`.
- [ ] **Step 3: Commit** with message `Parse Uconnect data into one snapshot`.

### Task 8: Vault, Face ID, snapshot cache, panel patch, alert rules

**Files:**
- Create: `ios/Forx/Store/Vault.swift`, `ios/Forx/Store/SnapshotCache.swift`, `ios/Forx/Model/PanelPatch.swift`, `ios/Forx/Model/AlertRules.swift`, and tests `SnapshotCacheTests.swift`, `PanelPatchTests.swift`, `AlertRulesTests.swift`

**Interfaces:**
- Produces:
  - `struct Vault`, Keychain service `com.milanpatel.Forx`, accessible `kSecAttrAccessibleAfterFirstUnlock`:
    - `func save(email:password:pin:) throws`;
    - `func load() -> (email: String, password: String, pin: String)?`;
    - `func saveSession(_:)`, `func loadSession() -> Session?`, `func clear()`.
  - `protocol FaceIDGate: Sendable { func confirm(reason: String) async -> Bool }`, with `LAFaceIDGate` using policy `.deviceOwnerAuthentication`.
  - `struct SnapshotCache`:
    - `init(url:)`;
    - `func save(_ s: JeepSnapshot) throws` writes with `.completeFileProtectionUntilFirstUserAuthentication`;
    - `func load() -> JeepSnapshot?`.
  - `func panelPatch(_ s: JeepSnapshot?, pending: Set<JeepCommand>, offline: Bool, message: String?, now: Date) -> [String: Any]`:
    - keys per Task 3's patch contract;
    - `updated` reads `"Updated now"` under 60 s, otherwise `"Updated N min ago"` / `"Updated N h ago"`.
  - `enum Alert: String, CaseIterable { leftUnlocked, lowTire, lowRange, chargingDone }`.
  - `func alerts(previous: JeepSnapshot?, current: JeepSnapshot, unlockedSince: Date?, now: Date) -> [Alert]`, with the thresholds from Global Constraints.

- [ ] **Step 1: Write failing tests.**
  - `SnapshotCacheTests.roundTrip`.
  - `SnapshotCacheTests.loadsLastSnapshotOffline`: save, then a new cache instance loads an equal snapshot.
  - `PanelPatchTests.supportedMapsToPanelKeys`: `[.lock, .unlock, .horn]` → `supported` == `["horn","lock"]`, sorted.
  - `PanelPatchTests.updatedCopy`: 30 s → "Updated now"; 180 s → "Updated 3 min ago".
  - `PanelPatchTests.nilSnapshotGivesNulls`.
  - `AlertRulesTests`: one test per alert at the boundary. 9 min 59 s unlocked → none; 10 min → `leftUnlocked`. 32 psi → none; 31 → `lowTire`. 40 mi → none; 39 → `lowRange`. charging true → false while plugged → `chargingDone`.
- [ ] **Step 2: Implement.** Vault and Face ID have no unit tests; they are checked live at Task 13.
- [ ] **Step 3: Commit** with message `Vault, cache, panel patch and alert rules`.

### Task 9: JeepStore

**Files:**
- Create: `ios/Forx/Store/JeepStore.swift`, `ios/ForxTests/JeepStoreTests.swift`

**Interfaces:**
- Consumes: `UconnectAPI`, `UconnectAuth`, `Vault`, `FaceIDGate`, `SnapshotCache`, `JeepSnapshot`, `panelPatch`.
- Produces `@Observable final class JeepStore`:
  - Properties:
    - `private(set) var snapshot: JeepSnapshot?`, `pending: Set<JeepCommand>`;
    - `offline: Bool`, `message: String?`;
    - `needsSignIn: Bool`, `vin: String?`.
  - `init(makeAPI: @escaping (Session) -> UconnectAPIProtocol, auth: UconnectAuthProtocol, vault: VaultProtocol, faceID: FaceIDGate, cache: SnapshotCache, now: @escaping () -> Date)`.
    - Define `UconnectAPIProtocol`, `UconnectAuthProtocol` and `VaultProtocol` here so tests can fake them; `UconnectAPI`, `UconnectAuth` and `Vault` conform.
  - Methods:
    - `func signIn(email:password:pin:) async throws(UconnectError)`;
    - `func signOut()`;
    - `func refresh() async`;
    - `func perform(_ cmd: JeepCommand, fromCarPlay: Bool = false) async`;
    - `var patch: [String: Any]`.
- Behaviour:
  - `refresh`:
    - loads the cache first, marks `offline` on `.network`;
    - re-logins once from the Vault when the session is near expiry or the API reports auth expiry;
    - on `.badLogin` sets `needsSignIn = true` and stops.
  - `perform`:
    - ignores a command already in `pending`;
    - for `.unlock` when `fromCarPlay == false`, requires `faceID.confirm(reason: "Unlock your Jeep")`, and a false result is a silent no-op;
    - inserts into `pending`, awaits `send`, and on success refreshes and removes;
    - on `.timeout`/`.commandFailed` removes and sets `message = "Jeep didn't answer. Try again."`, cleared after 4 s.

- [ ] **Step 1: Write failing tests** with fakes:
  - `secondTapWhilePendingIsIgnored`: one send recorded;
  - `failureReverts`;
  - `unlockNeedsFaceIDOnPhone`: denied → no send;
  - `unlockFromCarPlaySkipsFaceID`;
  - `lockSkipsFaceID`;
  - `reloginFailureStopsAndAsks`: exactly one login attempt, `needsSignIn == true`;
  - `offlineUsesCache`.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Commit** with message `JeepStore: refresh and commands`.

### Task 10: Mac checkpoint B

- [ ] Same as Task 6, for Tasks 7–9. Expected: all tests pass.

### Task 11: Panel web view and app wiring

**Files:**
- Create: `ios/Forx/UI/PanelWebView.swift`
- Modify: `ios/Forx/UI/RootView.swift`, `ios/Forx/App.swift`

**Interfaces:**
- Consumes: Task 3's JS contract, `JeepStore`.
- Produces: `struct PanelWebView: UIViewRepresentable`:
  - Serves the bundle's `Web/` folder through a `WKURLSchemeHandler` on scheme `forx`.
    - Loads `forx://app/index.html`.
    - Sets correct MIME types for html, js, css, glb, svg and png.
    - Sends the header `Access-Control-Allow-Origin: *`.
  - Message handler name `jeep`:
    - `{type:"ready"}` → push `store.patch`;
    - `{type:"command", action}` → map `lock→.lock`, `unlock→.unlock`, `climateOn→.climateOn`, `climateOff→.climateOff`, `lights→.lights`, `horn→.horn`, `gate→.gate`, then call `store.perform`.
  - Every `store` change pushes `window.jeepNative.apply(<json>)` via `evaluateJavaScript`.
  - Black background, `isOpaque = false` until first paint, no scroll bounce, pull-to-refresh via `UIRefreshControl` calling `store.refresh()`.
- `App.swift`:
  - on `.active`, refresh now and every 120 s;
  - on `.background`, schedule the BG task.

- [ ] **Step 1: Implement**, with `RootView` showing `PanelWebView` full screen.
- [ ] **Step 2: Commit** with message `Jeep Panel runs inside the iPhone app`.

### Task 12: Sign-in, Settings, background alerts

**Files:**
- Create: `ios/Forx/UI/SignInView.swift`, `ios/Forx/UI/SettingsView.swift`, `ios/Forx/Background/Refresher.swift`
- Modify: `RootView.swift`; `src/main.js` (the existing settings gear posts `{type:"settings"}`; Task 11's handler opens `SettingsView` as a sheet)

**Interfaces:**
- Consumes: `JeepStore`, `alerts(...)`.
- Produces:
  - `SignInView` with Email, Password and Uconnect PIN (4 digits, `.numberPad`) fields and a "Sign in" button.
    - Errors: `.badLogin` → "Email or password is wrong."; `.badPin` → "PIN is wrong."; `.network` → "No connection. Try again."
  - `SettingsView`: signed-in email, an "Alerts" toggle per `Alert` (units stay mi/psi/°F per spec §4, no units setting; the Apps tray list arrives in plan 3), and a "Sign out" button with destructive role and a confirmation.
    - Toggles are stored in UserDefaults key `alerts.<rawValue>`, default on.
  - `Refresher.register()` and `Refresher.schedule()` (earliest 15 min).
    - The handler refreshes, evaluates `alerts` against the cached previous snapshot, and posts a `UNNotificationRequest` per new alert with fixed copy:
      - "Your Jeep is unlocked"
      - "Low tire pressure: <corner> <psi> psi"
      - "Low range: <n> mi left"
      - "Charging done"
    - Ask notification permission after first sign-in.
- Motion: the sign-in sheet uses the system sheet; buttons use the system press feedback; no custom springs needed here.

- [ ] **Step 1: Implement.** `RootView` presents `SignInView` while `store.needsSignIn`.
- [ ] **Step 2: Rebuild web** with `npm run build:app` and run `node --test web-tests/` (PASS).
- [ ] **Step 3: Commit** with message `Sign-in, settings and alerts`.

### Task 13: Mac checkpoint C (live)

- [ ] **Step 1: Push.** Milan runs the Mac commands, picks his Personal Team once, and runs on his iPhone.
- [ ] **Step 2: Live check list.** Milan signs in himself; Claude never types credentials.
  - [ ] the panel loads with the 3D Jeep;
  - [ ] the name shows "Milan" and every control starts off;
  - [ ] range, odometer and tires show real values in mi/psi;
  - [ ] Lock spins, then confirms;
  - [ ] Unlock asks Face ID, then confirms;
  - [ ] unsupported buttons are hidden;
  - [ ] airplane mode → last data, dimmed;
  - [ ] sign out → sign-in sheet.
- [ ] **Step 3: Design check** against the live Jeep Panel and the ios-design-review checklist. Record fixes as tasks in this plan before closing.
- [ ] **Step 4: Fix and commit** each failure as `Fix: <what>`.
