import CoreLocation
import SwiftUI

// MARK: - Layout (pure, tested)

/// Sizes for the CarPlay window, from the v3 mockup (a 1514 × 628 app area with a 380 wide
/// Jeep panel), scaled to the window: one unit `u` = one mockup pixel. Type is clamped between a
/// readable floor and the mockup size. The right card's 12 pt inset and 26 pt radius are fixed
/// points (Global Constraints).
nonisolated struct DashboardLayout: Equatable, Sendable {
    static let mockHeight: CGFloat = 628
    static let mockPanel: CGFloat = 380
    static let cardInset: CGFloat = 12
    static let cardRadius: CGFloat = 26

    let size: CGSize

    /// 25% of the safe-area width.
    var panelWidth: CGFloat { (size.width * 0.25).rounded() }

    /// Mockup pixels → points: whichever of height or panel width is tighter.
    var u: CGFloat {
        max(0.1, min(size.height / Self.mockHeight, panelWidth / Self.mockPanel))
    }

    /// `mock` mockup pixels in points.
    func s(_ mock: CGFloat) -> CGFloat {
        mock * u
    }

    /// `mock` mockup pixels in points, kept between `floor` and the mockup size itself.
    func clamped(_ mock: CGFloat, floor: CGFloat) -> CGFloat {
        min(max(mock * u, floor), mock)
    }

    /// The right card, in window coordinates.
    var card: CGRect {
        CGRect(
            x: panelWidth, y: Self.cardInset,
            width: max(0, size.width - panelWidth - Self.cardInset),
            height: max(0, size.height - 2 * Self.cardInset))
    }

    // MARK: Left panel, top to bottom

    var padLeft: CGFloat { s(20) }
    var padRight: CGFloat { s(16) }
    var headerTop: CGFloat { s(20) }
    var avatar: CGFloat { clamped(40, floor: 30) }
    var headerGap: CGFloat { s(12) }
    var nameFont: CGFloat { clamped(19, floor: 15) }
    var subFont: CGFloat { clamped(13.5, floor: 11) }
    var headerBottom: CGFloat { headerTop + avatar }

    /// Narrow panels drop "· Parked" from the subtitle…
    var shortSubtitle: Bool { panelWidth < 200 }
    /// …and narrower ones the battery glyph too.
    var showsBattery: Bool { panelWidth >= 150 }

    /// "62% · 186 mi · Parked" → "62% · 186 mi" on a narrow panel.
    func subtitle(_ full: String) -> String {
        guard shortSubtitle else { return full }
        let parts = full.components(separatedBy: " · ")
        return parts.count > 2 ? parts.dropLast().joined(separator: " · ") : full
    }

    var statusFont: CGFloat { clamped(13, floor: 11) }
    var statusDot: CGFloat { max(s(6), 5) }
    var statusLineHeight: CGFloat { statusFont * 1.3 }
    /// The status line's centre: its bottom sits 22 above the panel bottom.
    var statusY: CGFloat { size.height - s(22) - statusLineHeight / 2 }

    /// The 3D Jeep: 10 under the header to just over the status line, a little wider than the
    /// panel (as in the mockup); the panel clips it.
    var jeep: CGRect {
        let top = headerBottom + s(10)
        let bottom = statusY - statusLineHeight / 2 - s(4)
        return CGRect(x: -s(14), y: top, width: panelWidth + s(28), height: max(0, bottom - top))
    }

    // MARK: Right card (card coordinates)

    /// The globe as in the mockup: 1.5 × the card height across, its centre 60% across and low,
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

// MARK: - Colours (mockup tokens)

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }

    static let dashText = Color(hex: 0xF5F5F7)
    static let dashSecondary = Color(hex: 0x8E8E93)
    static let dashGreen = Color(hex: 0x30D158)
    static let dashRed = Color(hex: 0xFF453A)
    static let dashIndigo = Color(hex: 0x5E5CE6)
    static let dashBlue = Color(hex: 0x0A84FF)
    static let dashNavy = Color(hex: 0x0A1626)
    static let dashDeep = Color(hex: 0x03060B)
}

// MARK: - View

/// The CarPlay window: the Jeep panel on the left (25%), the satellite globe card on the right.
/// A picture: every control is a real template button drawn by CarPlay over it.
/// Nothing here animates; the Jeep's one turn happens inside the web page.
struct DashboardView: View {
    let model: CarPlayModel
    let jeepState: [String: Any]
    /// The Jeep's last location (globe camera and dot).
    var location: CLLocationCoordinate2D? = nil
    /// Battery %, for the glyph.
    var battery: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let layout = DashboardLayout(size: geo.size)
            if model.signedIn {
                ZStack(alignment: .topLeading) {
                    panel(layout)
                        .frame(width: layout.panelWidth, height: geo.size.height, alignment: .topLeading)
                        .clipped()
                    card(layout)
                        .frame(width: layout.card.width, height: layout.card.height)
                        .offset(x: layout.card.minX, y: layout.card.minY)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            } else {
                Text("Sign in on your iPhone.")
                    .font(.system(size: layout.clamped(17, floor: 15), weight: .medium))
                    .foregroundStyle(Color.dashText)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
    }

    // MARK: Left panel

    private func panel(_ l: DashboardLayout) -> some View {
        ZStack(alignment: .topLeading) {
            JeepEmbedView(state: jeepState)
                .frame(width: l.jeep.width, height: l.jeep.height)
                .offset(x: l.jeep.minX, y: l.jeep.minY)
                .accessibilityHidden(true)

            header(l)
                .frame(width: l.panelWidth - l.padLeft - l.padRight, height: l.avatar, alignment: .leading)
                .offset(x: l.padLeft, y: l.headerTop)

            statusLine(l)
                .frame(width: l.panelWidth - l.s(24), height: l.statusLineHeight)
                .position(x: l.panelWidth / 2, y: l.statusY)
        }
    }

    private func header(_ l: DashboardLayout) -> some View {
        HStack(spacing: l.headerGap) {
            Text("M")
                .font(.system(size: l.avatar * 0.425, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: l.avatar, height: l.avatar)
                .background(
                    // CSS linear-gradient(160deg, #5E5CE6, #0A84FF)
                    LinearGradient(
                        colors: [.dashIndigo, .dashBlue],
                        startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97)),
                    in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: l.s(2)) {
                Text(model.name)
                    .font(.system(size: l.nameFont, weight: .semibold))
                    .tracking(-0.015 * l.nameFont)
                    .foregroundStyle(Color.dashText)
                    .lineLimit(1)
                HStack(spacing: l.subFont * 0.45) {
                    if l.showsBattery {
                        Image(systemName: BatterySymbol.name(battery))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                battery == nil ? Color.dashSecondary
                                    : (BatterySymbol.low(battery) ? Color.dashRed : Color.dashGreen),
                                Color.dashSecondary)
                            .font(.system(size: l.subFont, weight: .regular))
                            .accessibilityHidden(true)
                    }
                    Text(l.subtitle(model.subtitle))
                        .font(.system(size: l.subFont, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.dashSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// `● Locked · all doors closed`; a message replaces it while the store shows one (4 s).
    private func statusLine(_ l: DashboardLayout) -> some View {
        HStack(spacing: l.s(7)) {
            if let message = model.message {
                Text(message)
                    .foregroundStyle(Color.dashText)
            } else {
                if model.statusKnown {
                    Circle()
                        .fill(Color.dashGreen)
                        .frame(width: l.statusDot, height: l.statusDot)
                }
                Text(model.status)
                    .foregroundStyle(Color.dashSecondary)
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
                margins: l.mapMargins, dotSize: l.dotSize)
                .frame(width: map.width, height: map.height)
                .offset(x: map.minX, y: map.minY)
                .accessibilityHidden(true)

            // The mockup's .space: a faint navy glow rising from under the globe.
            RadialGradient(
                stops: [
                    .init(color: .dashNavy, location: 0),
                    .init(color: .dashDeep, location: 0.55),
                    .init(color: .black, location: 1),
                ],
                center: UnitPoint(x: 0.62, y: 0.85), startRadius: 0, endRadius: glow)
                .blendMode(.screen)
                .frame(width: l.card.width, height: l.card.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: l.card.width, height: l.card.height, alignment: .topLeading)
        .background(Color.black)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }
}
