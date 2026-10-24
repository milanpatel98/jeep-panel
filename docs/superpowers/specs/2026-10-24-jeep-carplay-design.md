# Jeep app for iPhone and CarPlay — design

Date: 2026-10-24 · Owner: Milan Patel · Status: waiting for Milan's review

## 1. What and why

A personal app for one car: Milan's black, lifted 2024 Wrangler 4-Door 4xe with the 12.3" Uconnect screen. It shows the real state of the Jeep and sends real commands (lock, unlock, and others the Jeep supports), on the iPhone and on the CarPlay screen.

- App name: Forx (from "4x", four-by-four and the 4xe).
- Audience: Milan only. No App Store, no other users, no server of ours.
- Signing: free Apple account. On the iPhone the app runs with real data and is re-run from Xcode every 7 days. CarPlay runs in Xcode's CarPlay simulator. Moving CarPlay to the real Jeep later needs the paid account and Apple's approval; the code stays the same and only a build switch changes.

Done means: Milan opens Xcode, presses Run, signs in once, sees his real Jeep, and lock/unlock work on the phone. In the simulator's CarPlay window, the 25/75 screen appears as in the approved mockup.

## 2. Rules from Milan

1. Design only the app area. Apple's CarPlay island and Jeep's frame are not ours.
2. Every control starts off. It turns on only after the Jeep confirms.
3. Whole screen black, one theme. Apple-native look, the best real icons (SF Symbols and official app icons), never Android-like.
4. CarPlay split: 25% Jeep panel, 75% apps.
5. Only important controls up front, the rest behind More.
6. The logged-in user's name ("Milan") instead of "Wrangler".
7. Commits by Milan Patel only. No passwords, PINs or tokens in files, chat or logs.

## 3. Screens

### iPhone: the existing Jeep Panel
- The iPhone screens are the Jeep Panel app Milan already has (this repo, live on GitHub Pages): same layout, same dark grey theme, same 3D Jeep and controls.
- What changes is the data. The placeholder values become real Uconnect data, and the buttons send real commands under the rules in §4.
- Added to it: Settings (sign in/out, units, Apps tray list, alerts on/off) and the Face ID step for Unlock.

### CarPlay (approved mockup `jeep-carplay-v3.png`)
- Left 25%, the Jeep panel:
  - "Milan" and a Settings button at the top;
  - the 3D Jeep on the mirror floor (top view, then 3/4);
  - status line;
  - Lock, Climate, Lights and More.
- Right 75%:
  - the Apple satellite globe, landing like Mercedes;
  - a Search pill that opens Apple Maps;
  - a small Apps button that opens the tray.
- More: Tires, Charging/EV, Roof view, Horn, Tailgate, Trip info.
- Apps tray, editable in Settings:
  - YouTube Music, Spotify, Apple Music, Podcasts, YouTube, Apple Maps, Google Maps, Waze, Phone, Messages;
  - tapping one switches CarPlay to that app;
  - YouTube plays inside our app.
- YouTube video only while the Jeep is stopped. The moment it moves, video pauses and audio continues.
- CarPlay never asks for input on the phone. If not signed in, it shows one line: "Sign in on your iPhone."

How CarPlay allows this:
- The app uses the navigation-style window, which is the only kind that may draw its own picture (the Jeep and the globe).
- CarPlay doesn't let custom drawings be tapped. Lock, Climate, Lights, More, Apps and Search are Apple's own CarPlay buttons placed over the picture.

## 4. How it behaves

| Action | Behavior |
|---|---|
| Open app | Pull status from Uconnect |
| App open | Refresh every 2 min; pull down to refresh |
| Background | iOS background refresh (iOS picks the time, about 15–60 min) to drive alerts |
| Tap a command | Button reacts on touch, shows a spinner, turns on only after the Jeep confirms (about 5–30 s); timeout 60 s → back to previous state + "Jeep didn't answer. Try again." |
| Unlock on iPhone | Face ID first |
| Unlock on CarPlay | No Face ID (you're in the car) |
| Old data | Each value shows its age; stale values are dimmed; offline shows last known state |
| Login expired | Signs in again silently from the Keychain; if the password changed, asks on the phone only |

Alerts (all on, each can be switched off in Settings):
- Jeep left unlocked for 10+ min while parked;
- any tire under 32 psi;
- range under 40 mi;
- charging done.

Commands shown are only those in the Jeep's own supported-command list, read at sign-in:
- Lock/Unlock (RDL/RDU) are confirmed working.
- Climate (remote start/precondition), Lights and Horn (horn & lights), and Tailgate appear only if the Jeep lists them. Otherwise they are hidden, not greyed.
- Fields Uconnect returns empty (windows, HVAC, liftgate) are hidden.

Units: mi, psi, °F.

## 5. Parts (one app, shared by both screens)

| Part | Job |
|---|---|
| UconnectClient | Swift port of the py-uconnect flow (Apache-2.0, credited): Gigya login → JWT → token exchange → Cognito credentials → SigV4-signed calls; PIN step; send command and poll its result |
| JeepStore | One observable state for both screens; unit conversion; hides empty fields; supported-command filter; staleness |
| Vault | Keychain items (sign-in, PIN, tokens), `AfterFirstUnlock` so CarPlay works with the phone locked; Face ID gate for Unlock |
| JeepScene | The existing three.js Jeep (embed build) inside a WKWebView, served from the app bundle through a custom URL scheme; Swift → JS calls: view, roof, lights, door, gate |
| GlobeView | MapKit satellite globe |
| PhoneUI | The Jeep Panel screens (the existing web app, bundled) plus native Settings and Face ID |
| CarPlayUI | Scene delegate, CPMapTemplate + window with the 25/75 picture, Apple buttons on top, More list, Apps tray |
| Alerts | Background refresh + local notifications (CarPlay-allowed) |

Swift 6 with main-actor-by-default and Approachable Concurrency. Logging uses `Logger` with private values, and no secret is ever logged. Project is described in XcodeGen `project.yml` and lives in `ios/` in this repo.

Motion: no-bounce springs by default, press feedback on every button, interruptible animations, and Reduce Motion respected.

## 6. Testing

- UconnectClient: Swift Testing unit tests against recorded sample responses (SigV4 signing, unit conversion, supported-command filter, timeout path). No live calls in tests.
- Live check by Milan: sign in, read status, lock and unlock on the phone.
- CarPlay: simulator at the widescreen size (1920×720) plus 800×480 and 1280×720; day and night.
- Design review against the approved mockup and the ios-design-review checklist before calling a sub-project done.

## 7. Build order

1. iPhone app: sign-in, status, commands, 3D Jeep, alerts.
2. CarPlay screen: 25/75 layout, buttons, More, Search → Apple Maps.
3. Apps tray and parked-only YouTube.

Each step ends with Milan running it in Xcode before the next starts.

## 8. Not in this version

- App Store release, other users, a server.
- Reading data from the OBD port.
- Real-Jeep CarPlay (needs the paid account and Apple's approval).
