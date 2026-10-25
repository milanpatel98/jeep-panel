import CoreGraphics
import Foundation
import Observation
import UIKit

// MARK: - Pan (pure, tested)

/// One drag on the CarPlay screen, from CarPlay's pan callbacks (cumulative translation).
/// The first 10 pt decide the axis and lock it for the whole drag. Sideways turns the Jeep 1:1
/// from where it locked, so nothing jumps; up and down does nothing (the roof is a map button).
nonisolated struct CarPlayPan: Sendable, Equatable {
    enum Axis: Sendable, Equatable { case horizontal, vertical }

    enum Action: Sendable, Equatable {
        /// Turn the Jeep by this many degrees (drag right: positive).
        case spin(Double)
        /// The sideways drag ended.
        case release
    }

    static let lockDistance: Double = 10
    static let degreesPerPoint: Double = 0.4

    private(set) var axis: Axis? = nil
    private var lastX: Double = 0

    init() {}

    mutating func update(_ t: CGPoint) -> Action? {
        guard t.x.isFinite, t.y.isFinite else { return nil }
        guard let axis else {
            guard Double(hypot(t.x, t.y)) >= Self.lockDistance else { return nil }
            axis = abs(t.x) >= abs(t.y) ? .horizontal : .vertical
            lastX = Double(t.x)
            return nil
        }
        guard axis == .horizontal else { return nil }
        let dx = Double(t.x) - lastX
        lastX = Double(t.x)
        return dx == 0 ? nil : .spin(dx * Self.degreesPerPoint)
    }

    mutating func end(velocity: CGPoint) -> Action? {
        axis == .horizontal ? .release : nil
    }
}

// MARK: - Drag → 3D Jeep

/// Carries CarPlay's pan callbacks (from `CarPlayTemplates`) to the 3D Jeep page
/// (`JeepEmbedView` sets `send`): a sideways drag turns the Jeep.
final class DashboardSpin {
    /// Runs `window.jeepEmbed.<call>` on the page; nil until the page's view is up.
    var send: ((String) -> Void)?

    private var pan: CarPlayPan?

    init() {}

    func began() {
        pan = CarPlayPan()
    }

    func changed(_ translation: CGPoint) {
        if pan == nil { began() }
        guard var p = pan else { return }
        let action = p.update(translation)
        pan = p
        if let action { perform(action) }
    }

    func ended(_ velocity: CGPoint) {
        guard var p = pan else { return }
        pan = nil
        if let action = p.end(velocity: velocity) { perform(action) }
    }

    private func perform(_ action: CarPlayPan.Action) {
        switch action {
        case .spin(let deg):
            send?("spin(\(deg))")
        case .release:
            send?("release()")
        }
    }
}

// MARK: - Apps tray

/// The Apps tray over the globe's top-right corner. Open: the map buttons become the four
/// favourite apps. Closes after 8 s without use, on any command, or when an app opens.
@Observable
final class AppTray {
    static let idleTimeout: Duration = .seconds(8)

    private(set) var isOpen = false
    @ObservationIgnored private var closer: Task<Void, Never>? = nil

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        if !isOpen { isOpen = true }
        armTimer()
    }

    func close() {
        closer?.cancel()
        closer = nil
        if isOpen { isOpen = false }
    }

    private func armTimer() {
        closer?.cancel()
        closer = Task { [weak self] in
            try? await Task.sleep(for: AppTray.idleTimeout)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}

// MARK: - App icons

/// The apps' real icons (bundled as `appicon-<id>`, see ios/README.md), drawn into the iOS icon
/// shape or a circle at 3x. An icon that isn't bundled falls back to its SF Symbol on a plain tile.
enum AppIconArt {
    /// The iOS icon mask's corner, as a share of the side.
    static let corner: CGFloat = 0.2237

    static func bundled(_ app: CarPlayApp) -> UIImage? {
        UIImage(named: app.icon)
    }

    static func image(_ app: CarPlayApp, side: CGFloat, circle: Bool, dark: Bool = true) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let shape = circle
            ? UIBezierPath(ovalIn: rect)
            : UIBezierPath(roundedRect: rect, cornerRadius: side * corner)
        let icon = bundled(app)
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            shape.addClip()
            if let icon {
                icon.draw(in: rect)
            } else {
                let tile = dark
                    ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)
                    : UIColor.white
                tile.setFill()
                shape.fill()
                let config = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
                let tint: UIColor = dark ? .white : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
                if let glyph = UIImage(systemName: app.symbol, withConfiguration: config)?
                    .withTintColor(tint, renderingMode: .alwaysOriginal) {
                    let s = glyph.size
                    glyph.draw(in: CGRect(x: (side - s.width) / 2, y: (side - s.height) / 2, width: s.width, height: s.height))
                }
            }
            // a hairline edge, as the Home Screen draws on light icons
            UIColor.black.withAlphaComponent(0.08).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
