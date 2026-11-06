import CoreLocation
import SwiftUI

// MARK: - Layout (pure, tested)

/// Sizes for the CarPlay window's safe area. The 3D page fills it; the car lives in a region that
/// keeps clear of the status row (top), CarPlay's map-button column (right) and, with the map
/// open, the map (the right 54%). Type is set in points for a 360 pt tall area and shrinks on
/// shorter ones down to a readable floor.
nonisolated struct DashboardLayout: Equatable, Sendable {
    static let designHeight: CGFloat = 360
    /// CarPlay's map buttons: a 44 pt column with its margins, at the trailing edge.
    static let buttonColumn: CGFloat = 70
    /// The status row's band at the top.
    static let statusBand: CGFloat = 40
    static let bottomInset: CGFloat = 6
    /// With the map open the car keeps this share of the width; the map takes the rest.
    static let jeepShare: CGFloat = 0.46
    /// Between the car's region and the divider.
    static let dividerGap: CGFloat = 10
    /// The map buttons' pitch and the bottom one's centre above the bottom edge (CarPlay's own).
    static let buttonPitch: CGFloat = 44
    static let buttonBottom: CGFloat = 22.5
    /// The loading Jeep's width.
    static let loaderWidth: CGFloat = 180
    /// The map slides over this curve, and so does the car (the page shares it).
    static let slide = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.52)

    /// The safe area's size.
    let size: CGSize

    /// `pt` at the design height, shrinking with shorter windows but never under `floor`.
    func type(_ pt: CGFloat, floor: CGFloat) -> CGFloat {
        min(pt, max(floor, pt * size.height / Self.designHeight))
    }

    /// Where the map's leading edge rests while open.
    var splitX: CGFloat { (size.width * Self.jeepShare).rounded() }

    /// How far the divider can be dragged to the right edge.
    var dividerTravel: CGFloat { max(1, size.width - splitX) }

    /// The car's region on the page: the whole area less the status band and the button column,
    /// or (map open) up to the divider less a gap. `dividerDx` is a finger's live pull to the right.
    func region(mapOpen: Bool, dividerDx: CGFloat = 0) -> CGRect {
        let right = mapOpen
            ? min(size.width - Self.buttonColumn, splitX + dividerDx - Self.dividerGap)
            : size.width - Self.buttonColumn
        return CGRect(
            x: 0, y: Self.statusBand, width: max(1, right),
            height: max(1, size.height - Self.statusBand - Self.bottomInset))
    }

    /// The region as the page takes it: `{x0, y0, x1, y1}` in CSS pixels (points).
    static func regionJSON(_ r: CGRect) -> String {
        "{\"x0\":\(Int(r.minX.rounded())),\"y0\":\(Int(r.minY.rounded())),\"x1\":\(Int(r.maxX.rounded())),\"y1\":\(Int(r.maxY.rounded()))}"
    }

    /// The map: from the divider to the trailing edge, full height. Closed: just off the right edge.
    func mapFrame(open: Bool, dividerDx: CGFloat = 0) -> CGRect {
        let x = open ? splitX + dividerDx : size.width
        return CGRect(x: x, y: 0, width: max(1, size.width - splitX), height: size.height)
    }

    /// The status row's origin and type.
    var statusOrigin: CGPoint { CGPoint(x: 20, y: 13) }
    var statusFont: CGFloat { type(13, floor: 11) }

    /// The centre y of CarPlay's map buttons, top to bottom, for `count` buttons.
    func buttonCentres(count: Int) -> [CGFloat] {
        (0..<max(0, count)).map { i in
            size.height - Self.buttonBottom - CGFloat(count - 1 - i) * Self.buttonPitch
        }
    }

    /// The tray panel's rect: behind the button column, as tall as its rows plus a title.
    func trayFrame(count: Int) -> CGRect {
        let rows = CGFloat(count) * Self.buttonPitch
        let height = rows + 46
        let width: CGFloat = 196
        return CGRect(x: size.width - width, y: size.height - height, width: width, height: height)
    }

    /// The toast (a store message) sits low in the car's region.
    var toastBottom: CGFloat { size.height - 14 }
}

/// The drawn battery capsule: how full, and when it turns red.
nonisolated enum BatteryGauge {
    /// 0…1, from the EV %.
    static func fill(_ percent: Int?) -> CGFloat {
        CGFloat(min(100, max(0, percent ?? 0))) / 100
    }

    /// Green above 20%, otherwise red.
    static func low(_ percent: Int?) -> Bool {
        (percent ?? 100) <= 20
    }
}

// MARK: - Colours

extension Color {
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

/// Night or day, as CarPlay's appearance says (the car's light sensor and headlights).
nonisolated struct DashboardTheme: Equatable, Sendable {
    let dark: Bool

    /// Night #000, day a soft white #F5F5F7.
    var background: Color { dark ? .black : Color(hex: 0xF5F5F7) }
    var text: Color { dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x1C1C1E) }
    var secondary: Color { dark ? Color(hex: 0x8E8E93) : Color(hex: 0x6E6E73) }
    var hairline: Color { dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12) }
    var handle: Color { dark ? Color.white.opacity(0.38) : Color.black.opacity(0.28) }
    var tray: Color { dark ? Color(hex: 0x1C1C1E, opacity: 0.92) : Color.white.opacity(0.94) }
    var trayEdge: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    var trayShadow: Color { dark ? Color.black.opacity(0.55) : Color.black.opacity(0.14) }
    var toast: Color { dark ? Color(hex: 0x2C2C2E, opacity: 0.94) : Color.white.opacity(0.96) }

    static let green = Color(hex: 0x30D158)
    static let amber = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)
}

// MARK: - View

/// The CarPlay window: the 3D Jeep full-screen (the page draws its call-outs and the roof strip),
/// a status row top-left, the map sliding in from the right when Earth is on, the Apps tray's
/// names behind the map buttons, Milan's Jeep while the page loads. A picture: every control is a
/// real template button drawn by CarPlay over it; fingers reach the 3D Jeep through `gestures`.
struct DashboardView: View {
    let model: CarPlayModel
    let jeepState: [String: Any]
    /// The Jeep's last location (the map's centre and dot).
    var location: CLLocationCoordinate2D? = nil
    /// Battery %, for the capsule.
    var battery: Int? = nil
    /// Charging now: a breathing bolt after the percentage.
    var charging: Bool = false
    /// CarPlay's appearance: night (true) or day.
    var dark: Bool = true
    var gestures: JeepGestures? = nil
    var motion: DashboardMotion? = nil
    var tray: AppTray? = nil

    private var theme: DashboardTheme { DashboardTheme(dark: dark) }
    private var mapOpen: Bool { motion?.mapOpen ?? false }
    private var dividerDx: CGFloat { motion?.dividerDx ?? 0 }

    var body: some View {
        GeometryReader { geo in
            // Everything keeps CarPlay's safe area (clear of the dock).
            let layout = DashboardLayout(size: geo.size)
            ZStack(alignment: .topLeading) {
                if model.signedIn {
                    JeepEmbedView(state: Self.pageState(jeepState, layout: layout, mapOpen: mapOpen), gestures: gestures, motion: motion)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityHidden(true)
                        .onAppear { wire(layout) }
                        .onChange(of: geo.size) { _, _ in wire(layout) }

                    statusRow(layout)
                        .offset(x: layout.statusOrigin.x, y: layout.statusOrigin.y)

                    toast(layout)

                    mapLayer(layout)

                    trayLayer(layout)

                    loadingLayer(layout)
                } else {
                    Text("Sign in on your iPhone.")
                        .font(.system(size: layout.type(17, floor: 15), weight: .medium))
                        .foregroundStyle(theme.text)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// The page's state with the car's region for this layout.
    static func pageState(_ state: [String: Any], layout: DashboardLayout, mapOpen: Bool) -> [String: Any] {
        var s = state
        let r = layout.region(mapOpen: mapOpen)
        s["region"] = ["x0": Int(r.minX.rounded()), "y0": Int(r.minY.rounded()), "x1": Int(r.maxX.rounded()), "y1": Int(r.maxY.rounded())]
        return s
    }

    /// The gestures need the layout's numbers for a divider drag.
    private func wire(_ layout: DashboardLayout) {
        guard let gestures else { return }
        gestures.dividerTravel = layout.dividerTravel
        gestures.regionJSON = { dx in DashboardLayout.regionJSON(layout.region(mapOpen: true, dividerDx: dx)) }
    }

    // MARK: Status row

    /// `P R N D` (the one in use bright), the battery capsule and `78%`, then `186 mi`.
    private func statusRow(_ l: DashboardLayout) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 5) {
                ForEach(CarPlayModel.gearLetters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: l.statusFont, weight: .semibold))
                        .foregroundStyle(letter == model.gear ? theme.text : theme.secondary.opacity(0.5))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.gear == "D" ? "Drive" : "Parked")

            if let ev = model.evText {
                HStack(spacing: 6) {
                    BatteryCapsule(percent: battery, edge: theme.secondary.opacity(0.5))
                        .accessibilityHidden(true)
                    Text(ev)
                        .font(.system(size: l.statusFont, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                    if charging {
                        BreathingBolt()
                            .accessibilityLabel("Charging")
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.rangeText)
                    .font(.system(size: l.statusFont, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Text("mi")
                    .font(.system(size: l.statusFont * 0.92, weight: .medium))
                    .foregroundStyle(theme.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: Toast

    /// A store message ("Jeep didn't answer. Try again.") in a pill at the bottom, while it lasts.
    private func toast(_ l: DashboardLayout) -> some View {
        ZStack(alignment: .bottom) {
            if let message = model.message {
                Text(message)
                    .font(.system(size: l.type(13, floor: 11), weight: .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.toast, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.trayEdge, lineWidth: 1))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: l.region(mapOpen: mapOpen).width, height: l.toastBottom, alignment: .bottom)
        .animation(.easeOut(duration: 0.25), value: model.message)
        .allowsHitTesting(false)
    }

    // MARK: Map

    /// Apple Maps' own look, sliding in from the right edge; a hairline and a pill handle mark the
    /// divider. A finger drag moves it without animation; open and close slide.
    private func mapLayer(_ l: DashboardLayout) -> some View {
        let frame = l.mapFrame(open: mapOpen, dividerDx: dividerDx)
        return ZStack(alignment: .leading) {
            JeepMapView(coordinate: location, dark: dark)
                .frame(width: frame.width, height: frame.height)
            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1, height: frame.height)
            Capsule()
                .fill(theme.handle)
                .frame(width: 4, height: 44)
                .offset(x: 6)
        }
        .frame(width: frame.width, height: frame.height, alignment: .leading)
        .offset(x: frame.minX)
        .animation(dividerDx == 0 ? DashboardLayout.slide : nil, value: mapOpen)
        // a finger moves it as is; letting go glides it back (the page glides the car the same way)
        .animation(dividerDx == 0 ? DashboardLayout.slide : nil, value: dividerDx)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: Apps tray

    /// A glass panel rising from the corner behind the map buttons (which are the four favourite
    /// apps while it's open), their names on the buttons' rows.
    private func trayLayer(_ l: DashboardLayout) -> some View {
        let open = tray?.isOpen ?? false
        let apps = CarPlayModel.favouriteApps
        let frame = l.trayFrame(count: apps.count)
        let centres = l.buttonCentres(count: apps.count)
        return ZStack(alignment: .topLeading) {
            if open {
                ZStack(alignment: .topLeading) {
                    UnevenRoundedRectangle(topLeadingRadius: 24, style: .continuous)
                        .fill(theme.tray)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 24, style: .continuous).strokeBorder(theme.trayEdge, lineWidth: 1))
                        .shadow(color: theme.trayShadow, radius: 22, y: 8)
                    Text("Apps")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                        .offset(x: 18, y: 14)
                    ForEach(Array(apps.enumerated()), id: \.element.title) { i, app in
                        Text(app.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                            .frame(width: frame.width - DashboardLayout.buttonColumn - 18, height: DashboardLayout.buttonPitch, alignment: .trailing)
                            .offset(x: 18, y: centres[i] - frame.minY - DashboardLayout.buttonPitch / 2)
                    }
                }
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .offset(x: frame.minX, y: frame.minY)
        .animation(open ? .timingCurve(0.22, 1, 0.36, 1, duration: 0.42) : .easeIn(duration: 0.18), value: open)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Loading

    /// Milan's Jeep until the page has painted its own (the same picture, same place), so there's
    /// never a blank window; the page then takes over, turns the wheels and fades into the 3D Jeep.
    private func loadingLayer(_ l: DashboardLayout) -> some View {
        let blank = (motion?.page ?? .blank) == .blank
        return ZStack {
            if blank {
                LoadingJeep(width: DashboardLayout.loaderWidth, progress: 0, tint: theme.text, line: theme.text.opacity(0.14))
            }
        }
        .frame(width: l.size.width, height: l.size.height)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading")
    }
}

/// Milan's Jeep (his drawing), a thin progress line under it: the still version the app shows
/// before the page's own, animated one is up.
struct LoadingJeep: View {
    let width: CGFloat
    let progress: Double
    let tint: Color
    let line: Color

    var body: some View {
        VStack(spacing: 18) {
            Image("jeep-logo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: width)
                .foregroundStyle(tint)
            ZStack(alignment: .leading) {
                Rectangle().fill(line).frame(height: 1)
                Rectangle().fill(tint).frame(width: width * 0.6 * progress, height: 2).offset(y: -0.5)
            }
            .frame(width: width * 0.6, height: 2)
        }
    }
}

// MARK: - Battery and bolt

/// The battery, drawn: a 24 × 11 capsule (3.5 corner, 1 pt edge), a 1.5 × 4 nub on the right,
/// and an inner fill inset 1.5 pt as wide as the charge: green, red at 20% or less.
struct BatteryCapsule: View {
    let percent: Int?
    let edge: Color

    var body: some View {
        let inner = CGSize(width: 24 - 3, height: 11 - 3)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(edge, lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(BatteryGauge.low(percent) ? DashboardTheme.red : DashboardTheme.green)
                    .frame(width: inner.width * BatteryGauge.fill(percent), height: inner.height)
                    .padding(.leading, 1.5)
            }
            .frame(width: 24, height: 11)
            UnevenRoundedRectangle(bottomTrailingRadius: 0.75, topTrailingRadius: 0.75, style: .continuous)
                .fill(edge)
                .frame(width: 1.5, height: 4)
        }
    }
}

/// `bolt.fill`, 11 pt green, its opacity breathing 0.45 ↔ 1 over 1.6 s; still with Reduce Motion.
/// Driven by a timeline, so the dashboard's no-animation transaction doesn't stop it.
struct BreathingBolt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            bolt(opacity: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                bolt(opacity: Self.opacity(at: context.date.timeIntervalSinceReferenceDate))
            }
        }
    }

    /// 1 at the start of each 1.6 s cycle, 0.45 halfway.
    nonisolated static func opacity(at t: TimeInterval) -> Double {
        0.725 + 0.275 * cos(2 * .pi * t / 1.6)
    }

    private func bolt(opacity: Double) -> some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DashboardTheme.green)
            .opacity(opacity)
    }
}
