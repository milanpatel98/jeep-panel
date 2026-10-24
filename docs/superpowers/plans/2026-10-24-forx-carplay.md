# Forx CarPlay Implementation Plan (sub-project 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Forx on the CarPlay screen (Xcode's CarPlay simulator, 12.3" widescreen): a 25% Jeep panel and a 75% globe, with real data and real commands from the iPhone app.

**Architecture:**
- A navigation-category CarPlay scene: `CPTemplateApplicationScene` with a `CPWindow` and `CPMapTemplate` as root.
- The window draws the picture: a SwiftUI dashboard with the 3D Jeep in a transparent WKWebView and an `MKMapView` globe.
- All taps go through Apple's template buttons, because CarPlay doesn't deliver touches to the window: map buttons, bar buttons, and the More and Apps templates.
- Data and commands come from the same `JeepStore` the phone uses.

**Tech Stack:**
- iOS: iOS 26, Swift 6, CarPlay, MapKit, WebKit, SwiftUI, Swift Testing, XcodeGen.
- Web: Vite 5 + three.js 0.169 for the embed page, node:test.

**Spec:** `docs/superpowers/specs/2026-10-24-jeep-carplay-design.md` (§3 CarPlay, §4). Approved look: `jeep-carplay-v3.png` (Home / More / Apps) and `jeep-roof-strip.png`. Plan 1 (`docs/superpowers/plans/2026-10-24-jeep-iphone-app.md`) is done.

## Global Constraints

- Everything in plan 1's Global Constraints still applies. That includes:
  - iOS 26 and Swift 6, with main-actor-by-default and approachable concurrency;
  - no third-party packages;
  - commits as Milan Patel with no AI lines;
  - no secrets in files or logs;
  - controls start off and turn on only after the Jeep confirms.
- CarPlay category: navigation. Entitlement `com.apple.developer.carplay-maps: true` applies to **simulator builds only**:
  - `CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*] = Forx/ForxCarPlay.entitlements`;
  - device builds carry no entitlement, so free signing keeps working.
- Design only the app area. Apple's island and Jeep's frame are not ours.
- Layout: left panel is 25% of the CarPlay safe area width, right 75%. Whole screen `#000`. Corner radius 26 pt on the right card.
- Left panel, top to bottom:
  - avatar "M", **"Milan"**, and a line `<ev%> · <range> mi · <Parked|Driving>`;
  - the 3D black Jeep on the mirror floor (top view, then the 3/4 view after 2.4 s);
  - a status line `● Locked · all doors closed`, with the green dot only when known;
  - a bottom row: Lock, Climate, Lights, More.
- Right card:
  - satellite globe (hybrid imagery, landing like Mercedes, the camera starting far out over the Jeep's last location);
  - a "Search Maps" pill;
  - a small Apps button at the top right.
- Taps:
  - `CPMapTemplate.mapButtons`, max 4: Lock, Climate, Lights, More. Icon-only images.
    - Off: white glyph on `#1C1C1E`.
    - On: black glyph on `#F5F5F7`.
    - Pending: 50% white glyph. Pending is drawn, not animated: map button images are static.
  - Only commands the Jeep supports appear, and More always does.
  - Leading bar button "Search" → `scene.open(URL(string: "maps://")!)`.
  - Trailing bar buttons: Apps (grid icon) and Settings (gear icon).
- More is a `CPListTemplate`: Tires (4 psi in one row), Charging, Roof (Top on / Panels off / Top off; changes the 3D Jeep only), Horn, Tailgate, Trip (odometer).
  - Command rows appear only if supported.
  - Data rows show "—" when unknown.
- The Apps tray is a `CPGridTemplate`, at most 8 buttons, in this order: YouTube Music, Spotify, Apple Music, Podcasts, Apple Maps, Google Maps, Waze, Phone.
  - Each opens its URL scheme through `scene.open`.
  - YouTube video waits for plan 3. Messages has no public open URL in CarPlay, so it is dropped (8-button cap).
- Unlock from CarPlay: no Face ID (`fromCarPlay: true`). Tailgate from CarPlay: no Face ID.
- Not signed in: the window shows one centred line, "Sign in on your iPhone.", and the map buttons are hidden.
- Type: SF Pro (system). Name 19 pt semibold. Sub-lines 13.5 pt medium in `#8E8E93`. Status 13 pt.
- Motion follows emil-design-eng and apple-design:
  - the Jeep's top → 3/4 turn eases in and out over 1.6 s;
  - nothing else animates on its own;
  - Reduce Motion skips the turn.
- Icons: SF Symbols, no custom drawings.
  - Lock `lock.fill` / `lock.open.fill`, Climate `fan.fill`, Lights `headlight.high.beam.fill`, More `ellipsis`.
  - Search `magnifyingglass`, Apps `square.grid.3x3.fill`, Settings `gearshape.fill`.

## Review Focus

1. **Phone locked or app never opened on the phone:** the CarPlay scene connects without the phone UI ever running. The store must still load from the Keychain and cache, and the dashboard shows the last snapshot.
   - Test: `CarPlayModelTests.showsCachedSnapshotWhenNoPhoneUI` (Task 3).
2. **Not signed in:** no map buttons, the sign-in line shows, and nothing crashes on a nil snapshot.
   - Test: `CarPlayModelTests.notSignedInHidesButtons` (Task 3).
3. **Command pending or failed on CarPlay:** the button shows pending and then returns to off, and the message appears as a short `CPAlertTemplate`-free banner line under the status line. No modal alerts while driving.
   - Test: `CarPlayModelTests.pendingThenFailureRevertsButton` (Task 3).
4. **Unsupported commands:** Climate, Lights, Horn and Tailgate are hidden if the Jeep doesn't list them, and More still shows the data rows.
   - Test: `CarPlayModelTests.unsupportedCommandsHidden` (Task 3).
5. **Scene disconnect and reconnect (unplugging):** the window and observers are released, and reconnecting rebuilds everything once.
   - Test: `CarPlaySceneTests.reconnectBuildsOnce` (Task 5), using a fake interface controller.

---

## File Structure

```
embed.html                         # (from scratchpad ios-wip) black page, canvas, loads src/embed.js
src/embed.js                       # 3D Jeep only: mirror floor, top → 3/4, jeepEmbed.apply(state); posts {type:"ready"}
src/embedState.js                  # pure: maps Swift state → jeep calls (tested)
web-tests/embed.test.js
vite.app.config.js                 # modify: rollupOptions.input = { main: index.html, embed: embed.html }
ios/project.yml                    # modify: CarPlay scene manifest, simulator-only entitlement
ios/Forx/ForxCarPlay.entitlements
ios/Forx/CarPlay/CarPlaySceneDelegate.swift   # connect/disconnect, window, interface controller
ios/Forx/CarPlay/CarPlayModel.swift           # pure: store state → what CarPlay shows (tested)
ios/Forx/CarPlay/CarPlayTemplates.swift       # map/bar buttons, More list, Apps grid from CarPlayModel
ios/Forx/CarPlay/DashboardView.swift          # SwiftUI 25/75 layout
ios/Forx/CarPlay/JeepEmbedView.swift          # transparent WKWebView on forx://app/embed.html
ios/Forx/CarPlay/GlobeView.swift              # MKMapView hybrid globe
ios/Forx/App.swift                            # modify: one shared JeepStore for both scenes (AppModel.shared)
ios/ForxTests/CarPlayModelTests.swift  CarPlaySceneTests.swift
```

### Task 1: 3D Jeep embed page

**Files:** Create `embed.html`, `src/embed.js`, `src/embedState.js`, `web-tests/embed.test.js`. Modify `vite.app.config.js`.

**Interfaces:**
- Consumes: `createJeep` from `src/jeep.js`.
  - Read the WIP `src/embed.js` and `embed.html` at `/tmp/claude-0/-home-claude/49428304-0dd0-528c-984a-fb334289ec08/scratchpad/ios-wip/` as the starting point: mirror floor, rim light, top view then hero.
- Produces:
  - `window.jeepEmbed.apply(state)`, where `state` is a subset of `{locked, lights, roof: 'on'|'panels'|'off', doors:{FL,FR,BL,BR}, gate, reducedMotion}`;
  - a `{type:"ready"}` post to `window.webkit.messageHandlers.jeep`;
  - pure `embedCalls(prev, next) -> Array<[method, ...args]>` in `src/embedState.js`.
- Defaults: lights off, roof 'on', doors and gate closed. The background is transparent, so the CarPlay panel's black shows through.

- [ ] **Step 1: Failing tests** in `web-tests/embed.test.js`:
  - `embedCallsOnlyDiffs`: `embedCalls({}, {lights:true})` deep-equals `[["setLights", true]]`;
  - `embedCallsRoof`;
  - `embedCallsDoors` (one per changed door).
- [ ] **Step 2:** `npm run test:web`. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** `embedState.js` and `embed.js`.
  - Keep `main()` async, wrapped with `.catch` posting `{type:"error"}`.
  - Add `embed` to `rollupOptions.input`.
- [ ] **Step 4:** `npm run test:web` passes, then `npm run build:app`. Expected: `ios/Forx/Web/embed.html` exists, and the phone's `index.html` still works (`npm run build` too).
- [ ] **Step 5: Commit** "3D Jeep page for CarPlay".

### Task 2: CarPlay scene and simulator-only entitlement

**Files:** Create `ios/Forx/ForxCarPlay.entitlements` and `ios/Forx/CarPlay/CarPlaySceneDelegate.swift` (skeleton). Modify `ios/project.yml` and `ios/Forx/App.swift`.

**Interfaces:**
- Produces:
  - `final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate`, using the window variant `templateApplicationScene(_:didConnect:to:)`;
  - `@MainActor enum AppModel { static let store: JeepStore }`, the one store shared by the phone and CarPlay. `App.swift` uses it instead of building its own.
- `project.yml`:
  - `UIApplicationSceneManifest` with `UIApplicationSupportsMultipleScenes: true`;
  - a `CPTemplateApplicationSceneSessionRoleApplication` entry with `UISceneClassName: CPTemplateApplicationScene`, `UISceneConfigurationName: CarPlay` and `UISceneDelegateClassName: $(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`;
  - the simulator-only `CODE_SIGN_ENTITLEMENTS` from Global Constraints.

- [ ] **Step 1: Failing test** `SmokeTests.carPlaySceneDeclared`: Bundle.main's Info dictionary has the CarPlay role with the delegate class name ending in `CarPlaySceneDelegate`.
- [ ] **Step 2: Implement.** On connect: keep the interface controller and window, set an empty `CPMapTemplate` as root, and set a black `UIViewController` as the window root. On disconnect: nil both.
- [ ] **Step 3: Commit** "CarPlay scene (simulator)".

### Task 3: CarPlayModel (pure)

**Files:** Create `ios/Forx/CarPlay/CarPlayModel.swift` and `ios/ForxTests/CarPlayModelTests.swift`.

**Interfaces:**
- Consumes: `JeepSnapshot`, `JeepCommand`, and the store's `pending`, `message`, `needsSignIn` and `climateOn` (read `JeepStore.swift` for the exact names).
- Produces:
  - `struct CarPlayModel: Equatable { let signedIn: Bool; let name: String; let subtitle: String; let status: String; let statusKnown: Bool; let message: String?; let buttons: [CarPlayButton]; let more: [CarPlayRow]; let apps: [CarPlayApp] }`;
  - `enum CarPlayButtonKind { lock, climate, lights, more }`;
  - `struct CarPlayButton: Equatable { kind; state: .off|.on|.pending; symbol: String }`;
  - `struct CarPlayRow: Equatable { title: String; detail: String; action: JeepCommand? ; roof: Bool }`;
  - `struct CarPlayApp: Equatable { title: String; url: URL; symbol: String }`;
  - `static func make(snapshot: JeepSnapshot?, pending: Set<JeepCommand>, climateOn: Bool, message: String?, signedIn: Bool, roof: String) -> CarPlayModel`.
- Copy rules:
  - Subtitle: `"\(ev)% · \(range) mi · Parked"`, with "—" for unknowns. "Parked" when `ignitionOn != true`, else "Driving".
  - Status: `"Locked · all doors closed"`, `"Unlocked"`, or `"<Driver door> open"` (attention list like the web), else "—".
  - Name is always "Milan".
  - Lock symbol: `lock.fill` when locked, `lock.open.fill` otherwise. Its state is `.on` only when unlocked.
  - Climate is `.on` when `climateOn`. Lights is always `.off` (momentary).
  - Apps URLs: `youtubemusic://`, `spotify://`, `music://`, `podcasts://`, `maps://`, `comgooglemaps://`, `waze://`, `tel://`.

- [ ] **Step 1: Failing tests:**
  - `showsCachedSnapshotWhenNoPhoneUI`;
  - `notSignedInHidesButtons` (buttons empty, signedIn false);
  - `pendingThenFailureRevertsButton`;
  - `unsupportedCommandsHidden` (supported `[.lock,.unlock]` → buttons `[lock, more]`, and More has no Horn or Tailgate rows but has Tires, Charging, Roof, Trip);
  - `subtitleCopy` (78 / 186 / Parked);
  - `appsOrderAndCap` (exactly 8, in the order above).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Commit** "What CarPlay shows".

### Task 4: Dashboard picture (window)

**Files:** Create `ios/Forx/CarPlay/DashboardView.swift`, `JeepEmbedView.swift` and `GlobeView.swift`. Modify `CarPlaySceneDelegate.swift` so the window root is `UIHostingController(rootView: DashboardView(...))`.

**Interfaces:**
- Consumes: `CarPlayModel`, `AppModel.store`, and the `forx://` scheme handler from `PanelWebView.swift`. Factor the handler into a reusable `ForxSchemeHandler` class if it isn't one already.
- Produces:
  - `struct DashboardView: View` with `let model: CarPlayModel` and `let jeepState: [String: Any]`, laid out to the Global Constraints sizes;
  - `JeepEmbedView: UIViewRepresentable`, which loads `forx://app/embed.html`, is non-opaque, has a clear background, ignores touches, and pushes `jeepEmbed.apply(...)` after ready;
  - `GlobeView: UIViewRepresentable` with an `MKMapView`:
    - `preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)`;
    - camera centred on the snapshot's lat/lng (0,0 if unknown), distance 22,000 km, pitch 0;
    - no POI clutter and no user interaction;
    - one small blue location dot (annotation) at the Jeep;
  - the "Search Maps" pill and Apps button drawn in the card's top corners, which match the template bar buttons.
- Observing the store: the same `withObservationTracking` re-arm pattern as `PanelWebView.Coordinator`.

- [ ] **Step 1: Implement**, following the v3 mockup measurements, scaled to the window's bounds (no fixed pixels):
  - left panel width = 25% of the window;
  - right card inset 12 pt, radius 26.
- [ ] **Step 2: Commit** "CarPlay dashboard picture".

### Task 5: Templates and taps

**Files:** Create `ios/Forx/CarPlay/CarPlayTemplates.swift` and `ios/ForxTests/CarPlaySceneTests.swift`. Modify `CarPlaySceneDelegate.swift`.

**Interfaces:**
- Consumes: `CarPlayModel`, `AppModel.store.perform(_:fromCarPlay:)`, and `CPTemplateApplicationScene.open(_:options:completionHandler:)`.
- Produces:
  - `@MainActor final class CarPlayTemplates`, with `init(interface: CarPlayInterface, open: @escaping (URL) -> Void, perform: @escaping (JeepCommand) -> Void)`;
  - `func update(_ model: CarPlayModel)`, which updates the existing `CPMapTemplate`'s `mapButtons` and bar buttons in place instead of rebuilding;
  - `protocol CarPlayInterface { func setRoot(_ t: CPTemplate); func push(_ t: CPTemplate) }`, which `CPInterfaceController` conforms to via an extension and tests fake.
- Taps:
  - Lock: `.unlock` when locked, else `.lock`.
  - Climate: `.climateOn` / `.climateOff`. Lights: `.lights`.
  - More: push the `CPListTemplate`, whose row handlers call `completion()` on every path. Roof rows change only the 3D state (`AppModel.roof`).
  - Apps: push the `CPGridTemplate`.
  - Search: open `maps://`.
  - Settings: push a `CPListTemplate` with "Signed in as Milan" (detail: email) and "Sign out on your iPhone" (no action).

- [ ] **Step 1: Failing tests:**
  - `mapButtonsMatchModel` (count and order);
  - `lockTapSendsUnlockWhenLocked`;
  - `searchOpensAppleMaps`;
  - `moreRowsCallCompletion`;
  - `reconnectBuildsOnce`.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Commit** "CarPlay buttons, More, Apps, Search".

### Task 6: Mac checkpoint: see it, polish it

- [ ] **Step 1:** Push. Run `forx-run.command` on the Mac. Expected: all tests pass, and Forx opens in the simulator.
- [ ] **Step 2:** In Simulator, use I/O → External Displays → CarPlay, at the widescreen size if offered (`defaults write com.apple.iphonesimulator CarPlayExtraOptions -bool YES` once). Open Forx on the CarPlay screen. Screenshot via computer use.
- [ ] **Step 3: Design review**, comparing the screenshot side by side with `jeep-carplay-v3.png` using the emil-design-eng / impeccable / ios-design-review checklists: alignment, spacing rhythm, type sizes, contrast, the Jeep sitting on the floor (not floating), the globe framing, and button states.
  - Record each difference as a fix. Fix and re-screenshot until it matches or beats the mockup.
- [ ] **Step 4:** Send Milan the screenshots.
