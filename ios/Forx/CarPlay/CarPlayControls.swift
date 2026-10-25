import CoreGraphics
import Foundation
import Observation
import UIKit

// MARK: - Pan (pure, tested)

/// One drag on the CarPlay screen, from CarPlay's pan callbacks (cumulative translation).
/// The first 10 pt decide the axis and lock it for the whole drag; after that it tracks 1:1
/// from where it locked, so nothing jumps. Sideways spins the Jeep; up and down steps the roof strip.
nonisolated struct CarPlayPan: Sendable, Equatable {
    enum Axis: Sendable, Equatable { case horizontal, vertical }

    enum Action: Sendable, Equatable {
        /// Turn the Jeep by this many degrees (drag right: positive).
        case spin(Double)
        /// The strip's thumb at this step, fractional while dragging.
        case strip(Double)
        /// The sideways drag ended.
        case release
        /// The vertical drag ended: settle on this step.
        case stripRelease(Int)
    }

    static let lockDistance: Double = 10
    static let degreesPerPoint: Double = 0.4
    static let pointsPerStep: Double = 40
    /// How far past the ends the thumb follows (in steps), with resistance.
    static let overshoot: Double = 0.35
    /// The release projects this many seconds of velocity, so a flick goes a step further.
    static let projection: Double = 0.1

    let startStep: Int
    let maxStep: Int
    private(set) var axis: Axis? = nil
    private(set) var position: Double
    private var origin: CGPoint = .zero
    private var lastX: Double = 0

    init(startStep: Int, maxStep: Int = CarPlayModel.roofSteps.count - 1) {
        self.maxStep = max(0, maxStep)
        self.startStep = min(max(0, startStep), self.maxStep)
        position = Double(self.startStep)
    }

    mutating func update(_ t: CGPoint) -> Action? {
        guard t.x.isFinite, t.y.isFinite else { return nil }
        guard let axis else {
            guard Double(hypot(t.x, t.y)) >= Self.lockDistance else { return nil }
            axis = abs(t.x) >= abs(t.y) ? .horizontal : .vertical
            origin = t
            lastX = Double(t.x)
            return nil
        }
        switch axis {
        case .horizontal:
            let dx = Double(t.x) - lastX
            lastX = Double(t.x)
            return dx == 0 ? nil : .spin(dx * Self.degreesPerPoint)
        case .vertical:
            let raw = Double(startStep) + Double(t.y - origin.y) / Self.pointsPerStep
            position = Self.band(raw, max: Double(maxStep))
            return .strip(position)
        }
    }

    mutating func end(velocity: CGPoint) -> Action? {
        switch axis {
        case nil:
            return nil
        case .horizontal:
            return .release
        case .vertical:
            let v = velocity.y.isFinite ? Double(velocity.y) : 0
            let projected = position + v * Self.projection / Self.pointsPerStep
            let step = Int(min(Double(maxStep), max(0, projected)).rounded())
            position = Double(step)
            return .stripRelease(step)
        }
    }

    /// Past either end the thumb keeps following, ever more slowly, up to `overshoot`.
    static func band(_ x: Double, max hi: Double) -> Double {
        if x < 0 { return -overshoot * (1 - 1 / (1 - x / overshoot * 0.5)) }
        if x > hi { return hi + overshoot * (1 - 1 / (1 + (x - hi) / overshoot * 0.5)) }
        return x
    }
}

// MARK: - Drag → 3D Jeep

/// Carries CarPlay's pan callbacks (from `CarPlayTemplates`) to the 3D Jeep page
/// (`JeepEmbedView` sets `send`). A vertical drag also sets the roof when it ends.
final class DashboardSpin {
    /// Runs `window.jeepEmbed.<call>` on the page; nil until the page's view is up.
    var send: ((String) -> Void)?

    private let currentStep: () -> Int
    private let setRoof: (String) -> Void
    private var pan: CarPlayPan?

    init(
        currentStep: @escaping () -> Int = { CarPlayModel.roofSteps.firstIndex(of: AppModel.roof) ?? 0 },
        setRoof: @escaping (String) -> Void = { AppModel.roof = $0 }
    ) {
        self.currentStep = currentStep
        self.setRoof = setRoof
    }

    func began() {
        pan = CarPlayPan(startStep: currentStep())
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
        case .strip(let pos):
            send?("strip(\(pos))")
        case .release:
            send?("release()")
        case .stripRelease(let step):
            send?("stripRelease(\(step))")
            if CarPlayModel.roofSteps.indices.contains(step) { setRoof(CarPlayModel.roofSteps[step]) }
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
