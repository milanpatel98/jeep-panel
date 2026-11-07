import SwiftUI
import UIKit

#if DEBUG
/// The CarPlay screen on the phone, for screenshots when the simulator's CarPlay window can't
/// be reached (`FORX_CP=demo-…-phone`): the dashboard at CarPlay's size in a landscape window,
/// with stand-ins for what CarPlay draws itself (its dock on the left, the map buttons in their
/// platters on the right). Debug builds only; the phone app otherwise never shows it.
struct CarPlayPreview: View {
    static let height: CGFloat = 360
    static let dock: CGFloat = 52
    /// CarPlay's map-button platter and column, as the simulator draws them.
    static let platter: CGFloat = 36
    static let buttonPitch: CGFloat = 44
    static let buttonColumn: CGFloat = 70

    @State private var tick = 0
    @State private var motion = DashboardMotion()
    @State private var gestures: JeepGestures? = nil

    var body: some View {
        GeometryReader { geo in
            let dark = !CarPlayDebug.forceDay
            let width = geo.size.width
            let dashboard = CarPlaySceneDelegate.dashboard(dark: dark, gestures: gestures, motion: motion)
            // no templates here to keep the gestures' roof current: the preview does it
            let _ = gestures?.roof = dashboard.model.roofKey
            ZStack(alignment: .topLeading) {
                (dark ? Color.black : Color(hex: 0xF5F5F7)).ignoresSafeArea()
                dashboard
                    .frame(width: width - Self.dock, height: Self.height)
                    .offset(x: Self.dock)
                // the dock, as the simulator shows it
                Rectangle()
                    .fill(dark ? Color(hex: 0x1C1C1E) : Color(hex: 0xE5E5EA))
                    .frame(width: Self.dock, height: Self.height)
                // the map buttons, bottom-up from the corner, in CarPlay's platters
                let buttons = Array(dashboard.model.buttons.prefix(CarPlayTemplates.maxMapButtons))
                ForEach(Array(buttons.enumerated()), id: \.offset) { i, b in
                    let y = Self.height - 22.5 - CGFloat(buttons.count - 1 - i) * Self.buttonPitch
                    ZStack {
                        Circle()
                            .fill(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                            .frame(width: Self.platter, height: Self.platter)
                        Image(uiImage: CarPlayTemplates.glyph(b.symbol, state: b.state, dark: dark))
                    }
                    .position(x: width - Self.buttonColumn / 2, y: y)
                }
            }
            .frame(width: width, height: Self.height, alignment: .topLeading)
            .environment(\.colorScheme, dark ? .dark : .light)
        }
        .ignoresSafeArea()
        .onAppear {
            gestures = JeepGestures(motion: motion)
            if let roof = CarPlayDebug.demoRoof { AppModel.roof = roof }
            if let mode = CarPlayDebug.demoMode { motion.mode = mode }
            if CarPlayDebug.demoMap { motion.mapOpen = true }
            CarPlayDebug.runDemoDrag(gestures, motion: motion)
            // CarPlay is wide: turn the phone
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
    }
}
#endif
