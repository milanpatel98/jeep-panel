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

    /// The panel's inner padding.
    var padLeft: CGFloat { 20 }
    var headerTop: CGFloat { min(16, size.height * 0.045) }

    var nameFont: CGFloat { type(13, floor: 11) }
    var heroFont: CGFloat { type(30, floor: 24) }
    var unitFont: CGFloat { type(15, floor: 12) }
    var batteryFont: CGFloat { type(13, floor: 11) }
    var nameLine: CGFloat { (nameFont * 1.25).rounded() }
    var heroLine: CGFloat { (heroFont * 1.15).rounded() }
    var headerHeight: CGFloat { nameLine + 2 + heroLine }
    var headerBottom: CGFloat { headerTop + headerHeight }

    /// Narrow panels drop the battery glyph and percentage.
    var showsBattery: Bool { panelWidth >= 150 }

    var statusFont: CGFloat { type(13, floor: 11) }
    var statusLineHeight: CGFloat { (statusFont * 1.3).rounded() }
    /// The status line's centre: its bottom sits as far above the panel bottom as the header's top.
    var statusY: CGFloat { size.height - headerTop - statusLineHeight / 2 }

    /// The 3D Jeep, from just under the header to just above the status line. It runs 10 pt
    /// past the panel's left edge (the panel clips it) and stops at its right edge, where the
    /// page draws the roof strip.
    var jeep: CGRect {
        let top = headerBottom + 2
        let bottom = statusY - statusLineHeight / 2 - 2
        return CGRect(x: -10, y: top, width: panelWidth + 10, height: max(0, bottom - top))
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

/// The battery glyph: the SF Symbol for the nearest 25% step.
nonisolated enum BatterySymbol {
    static func name(_ percent: Int?) -> String {
        let p = min(100, max(0, percent ?? 0))
        let step = Int((Double(p) / 25).rounded()) * 25
        return "battery.\(step)percent"
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
    /// Battery %, for the glyph.
    var battery: Int? = nil
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

            header(l)
                .frame(width: l.panelWidth - 2 * l.padLeft, height: l.headerHeight, alignment: .topLeading)
                .offset(x: l.padLeft, y: l.headerTop)

            statusLine(l)
                .frame(width: l.panelWidth - 2 * l.padLeft, height: l.statusLineHeight, alignment: .leading)
                .offset(x: l.padLeft, y: l.statusY - l.statusLineHeight / 2)
        }
    }

    /// "Milan", then the range as the hero number with the battery beside it.
    private func header(_ l: DashboardLayout) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.name)
                .font(.system(size: l.nameFont, weight: .medium))
                .foregroundStyle(theme.secondary)
                .frame(height: l.nameLine)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(model.rangeText)
                    .font(.system(size: l.heroFont, weight: .semibold))
                    .tracking(-0.02 * l.heroFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Text(" mi")
                    .font(.system(size: l.unitFont, weight: .medium))
                    .foregroundStyle(theme.secondary)

                if l.showsBattery, let ev = model.evText {
                    HStack(spacing: 4) {
                        Image(systemName: BatterySymbol.name(battery))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                BatterySymbol.low(battery) ? DashboardTheme.red : DashboardTheme.green,
                                theme.secondary)
                            .accessibilityHidden(true)
                        Text(ev)
                            .monospacedDigit()
                            .foregroundStyle(theme.secondary)
                    }
                    .font(.system(size: l.batteryFont, weight: .medium))
                    .padding(.leading, 10)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: l.heroLine, alignment: .leading)
        }
    }

    /// One word and a glyph ("Locked"); a store message replaces it while shown (4 s).
    /// Unknown shows nothing.
    private func statusLine(_ l: DashboardLayout) -> some View {
        Group {
            if let message = model.message {
                Text(message)
                    .foregroundStyle(theme.text)
            } else if let word = model.statusWord {
                HStack(spacing: 6) {
                    if let symbol = model.statusSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: l.statusFont * 0.85, weight: .semibold))
                            .foregroundStyle(DashboardTheme.tint(model.statusTint))
                            .accessibilityHidden(true)
                    }
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
