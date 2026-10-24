import CarPlay
import CoreLocation
import SwiftUI
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    /// Rebuild this often, so Climate turns off on screen when its 15 minutes run out.
    static let tickInterval: Duration = .seconds(30)

    private var interfaceController: CPInterfaceController?
    private var window: CPWindow?
    private var host: UIHostingController<DashboardView>?
    private var connected = false
    private var ticker: Task<Void, Never>? = nil
    private var motionObserver: (any NSObjectProtocol)? = nil

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.window = window

        let host = UIHostingController(rootView: Self.dashboard())
        host.view.backgroundColor = .black
        host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        self.host = host
        connected = true
        observe()
        startTicker()
        motionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            let delegate = self
            Task { @MainActor in delegate?.render() }
        }

        interfaceController.setRootTemplate(CPMapTemplate(), animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        connected = false
        ticker?.cancel()
        ticker = nil
        if let motionObserver { NotificationCenter.default.removeObserver(motionObserver) }
        motionObserver = nil
        host = nil
        self.interfaceController = nil
        self.window = nil
    }

    // MARK: Store → window

    /// Builds the dashboard under observation (store and roof). The first change re-runs this on
    /// the next main-actor turn, so a burst of changes becomes one rebuild.
    private func observe() {
        guard connected else { return }
        let view = withObservationTracking {
            Self.dashboard()
        } onChange: { [weak self] in
            let delegate = self
            Task { @MainActor in delegate?.observe() }
        }
        host?.rootView = view
    }

    /// A rebuild outside observation (ticker, Reduce Motion); the observation stays armed.
    private func render() {
        guard connected else { return }
        host?.rootView = Self.dashboard()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: CarPlaySceneDelegate.tickInterval)
                guard !Task.isCancelled, let self else { return }
                self.render()
            }
        }
    }

    /// The dashboard for the store's state now.
    private static func dashboard(now: Date = Date()) -> DashboardView {
        let store = AppModel.store
        let roof = AppModel.roof
        let snapshot = store.snapshot
        let climateOn = store.climateOnUntil.map { now < $0 } ?? false
        let model = CarPlayModel.make(
            snapshot: snapshot, pending: store.pending, climateOn: climateOn, message: store.message,
            signedIn: !store.needsSignIn, roof: roof, now: now)
        let state = JeepEmbedState.make(
            snapshot: snapshot, roof: roof, reducedMotion: UIAccessibility.isReduceMotionEnabled)
        var location: CLLocationCoordinate2D? = nil
        if let lat = snapshot?.latitude, let lng = snapshot?.longitude {
            location = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return DashboardView(model: model, jeepState: state, location: location, battery: snapshot?.evPercent)
    }
}
