import CoreLocation
import SwiftUI

// MARK: - Layout (pure, tested)

/// Sizes for the CarPlay window, from the v3 mockup (a 1514 × 628 app area with a 380 wide
/// Jeep panel), scaled to the window: one unit `u` = one mockup pixel. Text and controls keep a
/// small floor so they stay readable on 240 pt tall screens. The right card's 12 pt inset and
/// 26 pt radius are fixed points (Global Constraints).
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

    /// `mock` mockup pixels in points, at least `floor`.
    func s(_ mock: CGFloat, min floor: CGFloat = 0) -> CGFloat {
        max(mock * u, floor)
    }

    /// The right card, in window coordinates.
    var card: CGRect {
        CGRect(
            x: panelWidth, y: Self.cardInset,
            width: max(0, size.width - panelWidth - Self.cardInset),
            height: max(0, size.height - 2 * Self.cardInset))
    }

    // Left panel, top to bottom.

    var padLeft: CGFloat { s(20) }
    var padRight: CGFloat { s(16) }
    var headerTop: CGFloat { s(20) }
    /// Avatar and gear circles.
    var avatar: CGFloat { s(40, min: 22) }
    var headerGap: CGFloat { s(12) }
    var nameFont: CGFloat { s(19, min: 12) }
    var subFont: CGFloat { s(13.5, min: 9.5) }
    var headerBottom: CGFloat { headerTop + avatar }
    /// The gear hint only where the name and subtitle still have room beside it.
    var showsGear: Bool { panelWidth >= 140 }

    var statusFont: CGFloat { s(13, min: 9.5) }
    var statusDot: CGFloat { s(6, min: 4) }

    var tileSide: CGFloat { s(18) }
    var tileBottom: CGFloat { s(22) }
    var tileColumn: CGFloat { max(0, (panelWidth - 2 * tileSide) / 4) }
    /// A round tile: 60 in the mockup, never wider than its column.
    var tile: CGFloat { min(s(60, min: 28), max(0, tileColumn - s(4))) }
    var tileGap: CGFloat { s(7) }
    var labelFont: CGFloat { s(11.5, min: 8) }
    /// The top of the tile row (circles).
    var tilesTop: CGFloat { size.height - tileBottom - labelFont * 1.25 - tileGap - tile }

    /// The status line's centre: 89 above the tiles, as in the mockup, but below the header.
    var statusY: CGFloat { max(headerBottom + s(40), tilesTop - s(89)) }

    /// The 3D Jeep: just under the header to just over the tiles, a little wider than the
    /// panel (as in the mockup); the panel clips it.
    var jeep: CGRect {
        let top = headerBottom + s(6)
        return CGRect(
            x: -s(14), y: top,
            width: panelWidth + s(28), height: max(0, tilesTop - s(4) - top))
    }

    // Right card's glass controls (card coordinates).

    var glassInset: CGFloat { s(18, min: 10) }
    var glassHeight: CGFloat { s(50, min: 30) }
    var searchFont: CGFloat { s(17, min: 13) }
    var searchWidth: CGFloat {
        min(max(s(300), glassHeight * 5.6), card.width * 0.42)
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
    static let dashFill = Color(hex: 0x1C1C1E)
    static let dashGreen = Color(hex: 0x30D158)
    static let dashGlass = Color(hex: 0x1E1E20, opacity: 0.7)
    static let dashGlassText = Color(hex: 0xAEAEB2)
    static let dashIcon = Color(hex: 0xE5E5EA)
    static let dashGear = Color(hex: 0xD1D1D6)
    static let dashIndigo = Color(hex: 0x5E5CE6)
    static let dashBlue = Color(hex: 0x0A84FF)
}

// MARK: - View

/// The CarPlay window: the Jeep panel on the left (25%), the satellite globe card on the right.
/// A picture: the real taps are the map template's buttons, which these tiles and pills mirror.
/// Nothing here animates; the Jeep's one turn happens inside the web page.
struct DashboardView: View {
    let model: CarPlayModel
    let jeepState: [String: Any]
    /// The Jeep's last location (globe camera and dot).
    var location: CLLocationCoordinate2D? = nil
    /// Battery %, for the glyph's fill.
    var battery: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let layout = DashboardLayout(size: geo.size)
            if model.signedIn {
                ZStack(alignment: .topLeading) {
                    panel(layout)
                        .frame(width: layout.panelWidth, height: geo.size.height)
                        .clipped()
                    card(layout)
                        .frame(width: layout.card.width, height: layout.card.height)
                        .offset(x: layout.card.minX, y: layout.card.minY)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            } else {
                Text("Sign in on your iPhone.")
                    .font(.system(size: layout.s(17, min: 15), weight: .medium))
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
                .frame(width: l.panelWidth - l.padLeft - l.padRight, height: l.avatar)
                .offset(x: l.padLeft, y: l.headerTop)

            statusLine(l)
                .frame(width: l.panelWidth - l.s(24))
                .position(x: l.panelWidth / 2, y: l.statusY)

            tiles(l)
                .frame(width: l.panelWidth - 2 * l.tileSide)
                .offset(x: l.tileSide, y: l.tilesTop)
                .accessibilityHidden(true)
        }
        .frame(width: l.panelWidth, alignment: .topLeading)
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

            VStack(alignment: .leading, spacing: l.s(2)) {
                Text(model.name)
                    .font(.system(size: l.nameFont, weight: .semibold))
                    .foregroundStyle(Color.dashText)
                    .lineLimit(1)
                HStack(spacing: l.subFont * 0.52) {
                    BatteryGlyph(percent: battery, height: l.subFont * 0.78)
                    Text(model.subtitle)
                        .font(.system(size: l.subFont, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.dashSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: 0)

            if l.showsGear {
                // A hint of the Settings bar button.
                Image(systemName: "gearshape.fill")
                    .font(.system(size: l.avatar * 0.5, weight: .regular))
                    .foregroundStyle(Color.dashGear)
                    .frame(width: l.avatar, height: l.avatar)
                    .background(Color.dashFill, in: Circle())
                    .accessibilityHidden(true)
            }
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
        .minimumScaleFactor(0.75)
    }

    /// Lock, Climate, Lights, More: the map buttons' states, drawn. Fewer buttons stay centred.
    private func tiles(_ l: DashboardLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(model.buttons.enumerated()), id: \.offset) { _, button in
                VStack(spacing: l.tileGap) {
                    Image(systemName: button.symbol)
                        .font(.system(size: l.tile * 0.43, weight: .regular))
                        .foregroundStyle(Self.glyph(button.state))
                        .frame(width: l.tile, height: l.tile)
                        .background(Self.fill(button.state), in: Circle())
                    Text(Self.label(button.kind))
                        .font(.system(size: l.labelFont, weight: .medium))
                        .foregroundStyle(Color.dashSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: l.tileColumn)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Off: white on #1C1C1E. On: black on #F5F5F7. Pending: 50% white on #1C1C1E.
    private static func glyph(_ state: CarPlayButtonState) -> Color {
        switch state {
        case .off: .white
        case .on: .black
        case .pending: .white.opacity(0.5)
        }
    }

    private static func fill(_ state: CarPlayButtonState) -> Color {
        state == .on ? .dashText : .dashFill
    }

    private static func label(_ kind: CarPlayButtonKind) -> String {
        switch kind {
        case .lock: "Lock"
        case .climate: "Climate"
        case .lights: "Lights"
        case .more: "More"
        }
    }

    // MARK: Right card

    private func card(_ l: DashboardLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: DashboardLayout.cardRadius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            GlobeView(coordinate: location)
                .accessibilityHidden(true)

            searchPill(l)
                .offset(x: l.glassInset, y: l.glassInset)

            appsButton(l)
                .offset(x: l.card.width - l.glassInset - l.glassHeight, y: l.glassInset)
        }
        .frame(width: l.card.width, height: l.card.height, alignment: .topLeading)
        .background(Color.black)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }

    /// Mirrors the leading "Search" bar button.
    private func searchPill(_ l: DashboardLayout) -> some View {
        HStack(spacing: l.searchFont * 0.6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: l.searchFont * 1.05, weight: .medium))
            Text("Search Maps")
                .font(.system(size: l.searchFont, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.dashGlassText)
        .padding(.horizontal, l.glassHeight * 0.36)
        .frame(width: l.searchWidth, height: l.glassHeight, alignment: .leading)
        .modifier(Glass(shape: Capsule()))
        .accessibilityHidden(true)
    }

    /// Mirrors the trailing Apps bar button.
    private func appsButton(_ l: DashboardLayout) -> some View {
        Image(systemName: "square.grid.3x3.fill")
            .font(.system(size: l.glassHeight * 0.4, weight: .regular))
            .foregroundStyle(Color.dashIcon)
            .frame(width: l.glassHeight, height: l.glassHeight)
            .modifier(Glass(shape: Circle()))
            .accessibilityHidden(true)
    }
}

/// The mockup's glass: rgba(30,30,32,.7) over a thin material, with a hairline edge.
private struct Glass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(Color.dashGlass, in: shape)
            .background(.thinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// The small battery beside the subtitle: a grey outline with a green fill for the charge
/// (as in the mockup). Empty when the charge is unknown.
private struct BatteryGlyph: View {
    let percent: Int?
    let height: CGFloat

    var body: some View {
        let width = height * 2.1
        let line = max(1, height * 0.124)
        let gap = height * 0.133
        let inner = width - 2 * (line + gap)
        let level = CGFloat(min(100, max(0, percent ?? 0))) / 100
        RoundedRectangle(cornerRadius: height * 0.29, style: .continuous)
            .strokeBorder(Color.dashSecondary, lineWidth: line)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.12, style: .continuous)
                    .fill(Color.dashGreen)
                    .frame(width: inner * level, height: max(0, height - 2 * (line + gap)))
                    .padding(.leading, line + gap)
            }
            .accessibilityHidden(true)
    }
}
