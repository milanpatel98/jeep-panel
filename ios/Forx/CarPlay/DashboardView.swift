import CoreLocation
import SwiftUI

// MARK: - Layout (pure, tested)

/// Sizes for the CarPlay window: the Jeep panel takes the left 35%, the globe card the rest.
/// Type is set in points for a 360 pt tall window (960 × 360) and shrinks on shorter ones down
/// to a readable floor. The right card's 12 pt inset and 26 pt radius are fixed points.
nonisolated struct DashboardLayout: Equatable, Sendable {
    static let designHeight: CGFloat = 360
    static let panelShare: CGFloat = 0.35
    static let cardInset: CGFloat = 12
    static let cardRadius: CGFloat = 26

    let size: CGSize

    var panelWidth: CGFloat { (size.width * Self.panelShare).rounded() }

    /// `pt` at the design height, shrinking with shorter windows but never under `floor`.
    func type(_ pt: CGFloat, floor: CGFloat) -> CGFloat {
        min(pt, max(floor, pt * size.height / Self.designHeight))
    }

    /// The right card, in window coordinates.
    var card: CGRect {
        CGRect(
            x: panelWidth, y: Self.cardInset,
            width: max(0, size.width - panelWidth - Self.cardInset),
            height: max(0, size.height - 2 * Self.cardInset))
    }

    // MARK: Left panel, top to bottom

    /// What the page leaves free right of the car for the roof strip (CSS px = pt; `STRIP_W` in
    /// src/embed.js). The strip itself is 44 wide; the car tucks a little under its left edge.
    static let stripReserve: CGFloat = 28

    /// The hero row and energy row start here, from the panel's left.
    var padLeft: CGFloat { 20 }

    /// "Milan" sits beside CarPlay's search button (≈ x 4–40, y 4–40): vertically centred on it,
    /// starting at x 52, so there's no empty band over the panel.
    var nameLeading: CGFloat { 52 }
    var nameCenterY: CGFloat { 22 }
    var nameFont: CGFloat { type(15, floor: 13) }
    var nameLine: CGFloat { (nameFont * 1.25).rounded() }

    /// The range: 34 pt at 360 pt, its row's top at y 54.
    var heroTop: CGFloat { 54 }
    var heroFont: CGFloat { type(34, floor: 26) }
    var unitFont: CGFloat { type(15, floor: 12) }
    var heroLine: CGFloat { (heroFont * 1.2).rounded() }

    /// The battery capsule and percentage, just under the range (y 96 at 360 pt).
    var energyTop: CGFloat { heroTop + heroLine + 1 }
    var energyFont: CGFloat { type(13, floor: 11) }
    var energyLine: CGFloat { (energyFont * 1.25).rounded() }

    /// Narrow panels drop the battery capsule and percentage.
    var showsBattery: Bool { panelWidth >= 150 }

    var statusFont: CGFloat { type(13, floor: 11) }
    var statusLineHeight: CGFloat { (statusFont * 1.3).rounded() }
    /// The status line's centre: 22 pt above the bottom, under the middle of the Jeep (the
    /// page centres the Jeep in the area left of the roof strip).
    var statusY: CGFloat { size.height - 22 }
    var statusCenterX: CGFloat { (panelWidth - Self.stripReserve) / 2 }

    /// The 3D Jeep: the panel's full width, from under the energy row (y 112 at 360 pt) to
    /// 44 pt above the bottom. The page fits the whole car inside this frame, with margin.
    var jeep: CGRect {
        let top = energyTop + energyLine
        let bottom = size.height - 44
        return CGRect(x: 0, y: top, width: panelWidth, height: max(0, bottom - top))
    }

    // MARK: Right card (card coordinates)

    /// The globe: 1.5 × the card height across, its centre 60% across and low,
    /// so it runs off the bottom and right.
    var globeDiameter: CGFloat { card.height * 1.5 }
    var globeCenter: CGPoint { CGPoint(x: card.width * 0.6, y: card.height * 0.85) }

    /// The map view, centred on the globe and covering the whole card (it overflows the card).
    var mapFrame: CGRect {
        let c = globeCenter
        let a = max(c.x, card.width - c.x)
        let b = max(c.y, card.height - c.y)
        return CGRect(x: c.x - a, y: c.y - b, width: 2 * a, height: 2 * b)
    }

    /// The map's margins to the card's edges, so Apple's legal label stays inside the card.
    var mapMargins: EdgeInsets {
        let m = mapFrame
        return EdgeInsets(
            top: max(0, -m.minY), leading: max(0, -m.minX),
            bottom: max(0, m.maxY - card.height), trailing: max(0, m.maxX - card.width))
    }

    /// The Jeep's dot: 8–10 pt with the card's height.
    var dotSize: CGFloat { min(max(card.height * 0.03, 8), 10) }

    /// The Apps tray's icons: 48 pt on a 360 pt window.
    var trayIcon: CGFloat { type(48, floor: 36) }
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
    var card: Color { dark ? .black : .white }
    var text: Color { dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x1C1C1E) }
    var secondary: Color { dark ? Color(hex: 0x8E8E93) : Color(hex: 0x6E6E73) }
    var cardEdge: Color { dark ? Color.white.opacity(0.05) : Color.black.opacity(0.06) }
    var tray: Color { dark ? Color(hex: 0x1E1E20, opacity: 0.94) : Color.white.opacity(0.94) }
    var trayEdge: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    var trayShadow: Color { dark ? Color.black.opacity(0.6) : Color.black.opacity(0.14) }

    static let green = Color(hex: 0x30D158)
    static let amber = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)
    static let navy = Color(hex: 0x0A1626)
    static let deep = Color(hex: 0x03060B)

    static func tint(_ t: CarPlayTint?) -> Color {
        switch t {
        case .green: green
        case .amber: amber
        case nil: .clear
        }
    }
}

// MARK: - View

/// The CarPlay window: the Jeep panel on the left (35%), the globe card on the right, and the
/// Apps tray over the card's top-right corner while it's open. A picture: every control is a
/// real template button drawn by CarPlay over it; drags reach the 3D Jeep through `spin`.
struct DashboardView: View {
    let model: CarPlayModel
    let jeepState: [String: Any]
    /// The Jeep's last location (globe camera and dot).
    var location: CLLocationCoordinate2D? = nil
    /// Battery %, for the capsule.
    var battery: Int? = nil
    /// Charging now: a breathing bolt after the percentage.
    var charging: Bool = false
    /// CarPlay's appearance: night (true) or day.
    var dark: Bool = true
    var spin: DashboardSpin? = nil
    var tray: AppTray? = nil

    private var theme: DashboardTheme { DashboardTheme(dark: dark) }

    var body: some View {
        GeometryReader { geo in
            let layout = DashboardLayout(size: geo.size)
            ZStack(alignment: .topLeading) {
                if model.signedIn {
                    ZStack(alignment: .topLeading) {
                        panel(layout)
                            .frame(width: layout.panelWidth, height: geo.size.height, alignment: .topLeading)
                            .clipped()
                        card(layout)
                            .frame(width: layout.card.width, height: layout.card.height)
                            .offset(x: layout.card.minX, y: layout.card.minY)
                    }
                    .transaction { $0.animation = nil }

                    trayLayer(layout)
                } else {
                    Text("Sign in on your iPhone.")
                        .font(.system(size: layout.type(17, floor: 15), weight: .medium))
                        .foregroundStyle(theme.text)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        // the whole window, not CarPlay's safe area: the layout's numbers are window coordinates
        // ("Milan" centred on the search button at y 22)
        .ignoresSafeArea()
        .background(theme.background.ignoresSafeArea())
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    // MARK: Left panel

    private func panel(_ l: DashboardLayout) -> some View {
        ZStack(alignment: .topLeading) {
            JeepEmbedView(state: jeepState, spin: spin)
                .frame(width: l.jeep.width, height: l.jeep.height)
                .offset(x: l.jeep.minX, y: l.jeep.minY)
                .accessibilityHidden(true)

            Text(model.name)
                .font(.system(size: l.nameFont, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .frame(width: max(0, l.panelWidth - l.nameLeading - l.padLeft), height: l.nameLine, alignment: .leading)
                .offset(x: l.nameLeading, y: l.nameCenterY - l.nameLine / 2)

            hero(l)
                .frame(width: l.panelWidth - 2 * l.padLeft, height: l.heroLine, alignment: .leading)
                .offset(x: l.padLeft, y: l.heroTop)

            if l.showsBattery, let ev = model.evText {
                energy(l, ev)
                    .frame(width: l.panelWidth - 2 * l.padLeft, height: l.energyLine, alignment: .leading)
                    .offset(x: l.padLeft, y: l.energyTop)
            }

            statusLine(l)
                .frame(width: l.panelWidth - 2 * l.padLeft, height: l.statusLineHeight)
                .offset(x: l.statusCenterX - (l.panelWidth - 2 * l.padLeft) / 2, y: l.statusY - l.statusLineHeight / 2)
        }
    }

    /// The range as the hero number, " mi" on its baseline.
    private func hero(_ l: DashboardLayout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(model.rangeText)
                .font(.system(size: l.heroFont, weight: .semibold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(theme.text)
            Text(" mi")
                .font(.system(size: l.unitFont, weight: .medium))
                .foregroundStyle(theme.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// A drawn battery capsule, the EV %, and a breathing bolt while charging.
    private func energy(_ l: DashboardLayout, _ ev: String) -> some View {
        HStack(spacing: 6) {
            BatteryCapsule(percent: battery, edge: theme.secondary.opacity(0.45))
                .accessibilityHidden(true)
            Text(ev)
                .font(.system(size: l.energyFont, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.secondary)
            if charging {
                BreathingBolt()
                    .accessibilityLabel("Charging")
            }
        }
        .lineLimit(1)
    }

    /// A soft glowing dot and one word ("Locked"), centred under the Jeep; a store message
    /// replaces it while shown (4 s). Unknown shows nothing.
    private func statusLine(_ l: DashboardLayout) -> some View {
        Group {
            if let message = model.message {
                Text(message)
                    .foregroundStyle(theme.text)
                    .minimumScaleFactor(0.8)
            } else if let word = model.statusWord {
                HStack(spacing: 7) {
                    let tint = DashboardTheme.tint(model.statusTint)
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .shadow(color: tint, radius: 4)
                        .accessibilityHidden(true)
                    Text(word)
                        .foregroundStyle(theme.text)
                }
            }
        }
        .font(.system(size: l.statusFont, weight: .medium))
        .lineLimit(1)
    }

    // MARK: Right card

    private func card(_ l: DashboardLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: DashboardLayout.cardRadius, style: .continuous)
        let map = l.mapFrame
        let glow = max(l.card.width, l.card.height) * 0.9
        return ZStack(alignment: .topLeading) {
            GlobeView(
                coordinate: location, globeRadius: l.globeDiameter / 2,
                margins: l.mapMargins, dotSize: l.dotSize, dark: dark)
                .frame(width: map.width, height: map.height)
                .offset(x: map.minX, y: map.minY)
                .accessibilityHidden(true)

            Group {
                if dark {
                    // Night: a faint navy glow rising from under the globe.
                    RadialGradient(
                        stops: [
                            .init(color: DashboardTheme.navy, location: 0),
                            .init(color: DashboardTheme.deep, location: 0.55),
                            .init(color: .black, location: 1),
                        ],
                        center: UnitPoint(x: 0.62, y: 0.85), startRadius: 0, endRadius: glow)
                        .blendMode(.screen)
                } else {
                    // Day: only a very soft light grey behind the globe.
                    RadialGradient(
                        stops: [
                            .init(color: Color(hex: 0xE6E6EB), location: 0),
                            .init(color: Color(hex: 0xF3F3F6), location: 0.5),
                            .init(color: .white, location: 1),
                        ],
                        center: UnitPoint(x: 0.6, y: 0.85), startRadius: 0, endRadius: glow)
                        .blendMode(.multiply)
                }
            }
            .frame(width: l.card.width, height: l.card.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: l.card.width, height: l.card.height, alignment: .topLeading)
        .background(theme.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.cardEdge, lineWidth: 1))
    }

    // MARK: Apps tray

    /// The tray grows out of the Apps button's corner (top-right): in 200 ms ease-out, out 150 ms.
    private func trayLayer(_ l: DashboardLayout) -> some View {
        let open = tray?.isOpen ?? false
        return ZStack(alignment: .topTrailing) {
            if open {
                trayCard(l)
                    .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .frame(width: l.card.width - 2 * DashboardLayout.cardInset, alignment: .topTrailing)
        .offset(x: l.card.minX + DashboardLayout.cardInset, y: l.card.minY + DashboardLayout.cardInset)
        .animation(open ? .easeOut(duration: 0.2) : .easeIn(duration: 0.15), value: open)
        .allowsHitTesting(false)
    }

    private func trayCard(_ l: DashboardLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let side = l.trayIcon
        return VStack(alignment: .leading, spacing: 12) {
            Text("Apps")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondary)
                .padding(.leading, 4)
            HStack(alignment: .top, spacing: 8) {
                ForEach(CarPlayModel.favouriteApps, id: \.title) { app in
                    VStack(spacing: 6) {
                        Image(uiImage: AppIconArt.image(app, side: side, circle: false, dark: dark))
                            .resizable()
                            .frame(width: side, height: side)
                        Text(app.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: side + 18)
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))
        .background(theme.tray, in: shape)
        .overlay(shape.strokeBorder(theme.trayEdge, lineWidth: 1))
        .shadow(color: theme.trayShadow, radius: dark ? 25 : 16, y: dark ? 20 : 8)
        .accessibilityHidden(true)
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
