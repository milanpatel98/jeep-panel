import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// The whole Earth as a satellite globe on black, seen from far out over the Jeep's last
/// location, with one small blue dot on the Jeep. Picture only: no touches, no POIs, no
/// compass or scale. Apple's legal label stays (MapKit requires it).
struct GlobeView: UIViewRepresentable {
    /// Far enough out to see the whole globe.
    static let distance: CLLocationDistance = 22_000_000

    /// The Jeep's location; nil → the camera looks at 0,0 and there's no dot.
    let coordinate: CLLocationCoordinate2D?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GlobeMapView {
        let map = GlobeMapView(frame: .zero)
        let config = MKHybridMapConfiguration(elevationStyle: .realistic)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        map.preferredConfiguration = config
        map.overrideUserInterfaceStyle = .dark
        map.backgroundColor = .black

        map.isUserInteractionEnabled = false
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false

        map.delegate = context.coordinator
        context.coordinator.show(coordinate, on: map)
        return map
    }

    func updateUIView(_ map: GlobeMapView, context: Context) {
        context.coordinator.show(coordinate, on: map)
    }

    static func dismantleUIView(_ map: GlobeMapView, coordinator: Coordinator) {
        map.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var dot: MKPointAnnotation? = nil
        private var shownKey: [Double]? = nil
        private var shownOnce = false

        /// Points the camera and moves the dot, only when the location changed. No animation.
        func show(_ coordinate: CLLocationCoordinate2D?, on map: GlobeMapView) {
            let valid = coordinate.flatMap { CLLocationCoordinate2DIsValid($0) ? $0 : nil }
            let key = valid.map { [$0.latitude, $0.longitude] }
            guard !shownOnce || key != shownKey else { return }
            shownOnce = true
            shownKey = key

            let center = valid ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            map.globeCamera = MKMapCamera(
                lookingAtCenter: center, fromDistance: GlobeView.distance, pitch: 0, heading: 0)

            if let valid {
                if let dot {
                    dot.coordinate = valid
                } else {
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = valid
                    map.addAnnotation(annotation)
                    dot = annotation
                }
            } else if let dot {
                map.removeAnnotation(dot)
                self.dot = nil
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let id = JeepDotView.reuseID
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? JeepDotView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            return view
        }
    }
}

/// An `MKMapView` that re-applies its camera whenever its size changes: the camera set before
/// the first layout (zero frame) would otherwise be lost.
final class GlobeMapView: MKMapView {
    var globeCamera: MKMapCamera? {
        didSet { applyCamera() }
    }

    private var laidOutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize {
            laidOutSize = bounds.size
            applyCamera()
        }
    }

    private func applyCamera() {
        guard let globeCamera, bounds.width > 0, bounds.height > 0 else { return }
        setCamera(globeCamera, animated: false)
    }
}

/// The Jeep on the globe: a small blue dot (#0A84FF) in a white ring.
final class JeepDotView: MKAnnotationView {
    static let reuseID = "jeep"
    static let size: CGFloat = 14
    static let ring: CGFloat = 2.5

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        let size = Self.size
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        canShowCallout = false
        isEnabled = false
        displayPriority = .required
        backgroundColor = .white
        layer.cornerRadius = size / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 3
        layer.shadowOffset = .zero

        let inner = CALayer()
        let d = size - 2 * Self.ring
        inner.frame = CGRect(x: Self.ring, y: Self.ring, width: d, height: d)
        inner.cornerRadius = d / 2
        inner.backgroundColor = UIColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1).cgColor
        layer.addSublayer(inner)
    }
}
