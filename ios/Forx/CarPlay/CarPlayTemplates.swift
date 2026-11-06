import CarPlay
import os
import UIKit

private let panLog = Logger(subsystem: "com.milanpatel.Forx", category: "pan")

/// What the templates need from CarPlay's interface controller; tests fake it.
protocol CarPlayInterface {
    func setRoot(_ t: CPTemplate)
    func push(_ t: CPTemplate)
    /// The template on screen (CPInterfaceController already has it).
    var topTemplate: CPTemplate? { get }
}

extension CPInterfaceController: CarPlayInterface {
    func setRoot(_ t: CPTemplate) {
        setRootTemplate(t, animated: false, completion: nil)
    }

    func push(_ t: CPTemplate) {
        pushTemplate(t, animated: true, completion: nil)
    }
}

/// TEMPORARY diagnostics for the CarPlayTemplateUIHost crash. Debug builds only; reads the
/// FORX_CP environment variable: nobars, nomap, bare, listroot, demo. Anything else: normal.
/// `demo` shows a fixture Jeep (signed in, 186 mi, locked) so the screen can be judged in the
/// simulator without an account. Release builds never see any of it.
enum CarPlayDebug {
    static var mode: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["FORX_CP"]
        #else
        return nil
        #endif
    }
    static var skipBarButtons: Bool { mode == "nobars" || mode == "bare" }
    static var skipMapButtons: Bool { mode == "nomap" || mode == "bare" }
    static var skipMapDelegate: Bool { mode == "bare" }
    static var listRoot: Bool { mode == "listroot" }
    /// `demo`, or `demo-open` (the driver's door and the tailgate open, unlocked, charging) and
    /// `-day` (CarPlay's day appearance, whatever the simulator says): `demo-open-day`.
    static var demo: Bool { mode?.hasPrefix("demo") == true }
    static var demoOpen: Bool { demo && mode?.contains("open") == true }
    static var forceDay: Bool { demo && mode?.contains("day") == true }

    /// The demo Jeep (`FORX_CP=demo…`, Debug only): nil otherwise.
    static func demoSnapshot(now: Date = Date()) -> JeepSnapshot? {
        #if DEBUG
        guard demo else { return nil }
        let open = demoOpen
        return JeepSnapshot(
            nickname: "Jeep", locked: !open, doorsOpen: open ? ["driver"] : [], tailgateOpen: open,
            rangeMiles: 186, fuelPercent: 64, evPercent: 78, pluggedIn: open, charging: open,
            chargeMinutesLeft: open ? 95 : nil, tiresPsi: ["FL": 36, "FR": 36, "RL": 35, "RR": 36],
            odometerMiles: nil, latitude: 39.7555, longitude: -105.2211,
            supported: [.lock, .unlock, .climateOn, .climateOff, .lights, .horn],
            updatedAt: now.addingTimeInterval(-38 * 60), ignitionOn: false, gasRangeMiles: 165)
        #else
        return nil
        #endif
    }
}

/// The CarPlay templates: one map template whose buttons are updated in place, plus the More
/// list, the Apps grid and Settings, pushed on tap. Map buttons: Jeep (views), Lock, Earth (the
/// map) and Apps (the tray: the map buttons become the four favourite apps until one opens, a
/// command runs, or 8 s pass). Bar buttons (they hide when the screen isn't touched): Roof
/// (steps the roof, for cars and the simulator that send no drags) and More.
/// Fingers: CarPlay's pan callbacks (and, on iOS 26 cars, zoom and rotation) reach the 3D Jeep
/// through `gestures`; the map never pans.
@MainActor
final class CarPlayTemplates: NSObject, CPMapTemplateDelegate {
    let mapTemplate = CPMapTemplate()
    /// The map buttons now shown, top to bottom (mirrors `mapTemplate.mapButtons`); empty while
    /// the tray shows its apps instead.
    private(set) var shownButtons: [CarPlayButton] = []
    /// The apps on the map buttons while the tray is open.
    private(set) var shownApps: [CarPlayApp] = []
    let tray: AppTray
    let gestures: JeepGestures?
    /// What the map buttons were last drawn for, so an unchanged state reassigns nothing.
    private var mapKey: MapKey?

    private struct MapKey: Equatable {
        let buttons: [CarPlayButton]
        let dark: Bool
        let trayOpen: Bool
    }

    private let interface: any CarPlayInterface
    private let open: (URL) -> Void
    private let perform: (JeepCommand) -> Void
    private let setRoof: (String) -> Void
    private let email: () -> String?
    private var model: CarPlayModel?
    /// What the bar buttons were last built for (nil: not yet).
    private var barsKey: BarsKey?

    private struct BarsKey: Equatable {
        let signedIn: Bool
        let trayOpen: Bool
        let roof: String
        let dark: Bool
    }
    /// The rows / settings the on-screen lists were last filled with.
    private var moreListRows: [CarPlayRow] = []
    private var settingsListKey: SettingsKey?

    private struct SettingsKey: Equatable {
        let signedIn: Bool
        let email: String
    }

    /// Lists on screen; CarPlay releases them when popped, so these go nil by themselves.
    private weak var moreList: CPListTemplate?
    private weak var settingsList: CPListTemplate?

    static let maxMapButtons = 4
    static let maxGridButtons = 8

    /// The dashboard's state the buttons change (the map, the Jeep's view).
    var motion: DashboardMotion? { gestures?.motion }

    init(
        interface: any CarPlayInterface,
        open: @escaping (URL) -> Void,
        perform: @escaping (JeepCommand) -> Void,
        setRoof: @escaping (String) -> Void = { AppModel.roof = $0 },
        email: @escaping () -> String? = { AppModel.store.email },
        tray: AppTray = AppTray(),
        gestures: JeepGestures? = nil
    ) {
        self.interface = interface
        self.open = open
        self.perform = perform
        self.tray = tray
        self.gestures = gestures
        self.setRoof = setRoof
        self.email = email
        super.init()
        gestures?.closeMap = { [weak self] in self?.setMap(open: false) }
        // The host's view controller (share button, etc.) talks to the delegate; without one
        // it crashes CarPlayTemplateUIHost. Set before the template becomes root.
        if !CarPlayDebug.skipMapDelegate { mapTemplate.mapDelegate = self }
        // Roof and More fade away when the screen isn't touched and come back on any touch.
        // The map buttons stay.
        mapTemplate.automaticallyHidesNavigationBar = true
        mapTemplate.hidesButtonsWithNavigationBar = false
        if CarPlayDebug.listRoot {
            interface.setRoot(CPListTemplate(title: "Forx", sections: []))
        } else {
            interface.setRoot(mapTemplate)
        }
    }

    // MARK: CPMapTemplateDelegate

    /// Forx is not a navigation app: no navigation metadata is provided.
    func mapTemplateShouldProvideNavigationMetadata(_ mapTemplate: CPMapTemplate) -> Bool {
        false
    }

    /// iOS 26.4+ route sharing: Forx shares no routes. Declared as a plain @objc method so it
    /// builds whether or not the SDK in use already lists it in CPMapTemplateDelegate.
    @objc func mapTemplateShouldProvideRouteSharing(_ mapTemplate: CPMapTemplate) -> Bool {
        false
    }

    // MARK: Fingers → 3D Jeep

    /// Touch-screen drags. Apple: "May not be called when connected to some CarPlay systems";
    /// the Xcode simulator's CarPlay window sends none, so the Roof bar button and the Jeep
    /// button cover what a drag does there. The map never pans.
    func mapTemplateDidBeginPanGesture(_ mapTemplate: CPMapTemplate) {
        panLog.notice("pan began")
        gestures?.began()
    }

    func mapTemplate(
        _ mapTemplate: CPMapTemplate, didUpdatePanGestureWithTranslation translation: CGPoint, velocity: CGPoint
    ) {
        gestures?.changed(translation)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, didEndPanGestureWithVelocity velocity: CGPoint) {
        panLog.notice("pan ended")
        gestures?.ended(velocity)
    }

    /// Two fingers (iOS 26 cars): a pinch zooms the Jeep, a twist turns it.
    func mapTemplateDidBeginZoomGesture(_ mapTemplate: CPMapTemplate) {
        panLog.notice("zoom began")
        gestures?.zoomBegan()
    }

    func mapTemplate(
        _ mapTemplate: CPMapTemplate, didUpdateZoomGestureWithCenter center: CGPoint, scale: CGFloat, velocity: CGFloat
    ) {
        gestures?.zoom(scale: scale)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, didEndZoomGestureWithVelocity velocity: CGFloat) {
        gestures?.zoomEnded()
    }

    func mapTemplateDidBeginRotationGesture(_ mapTemplate: CPMapTemplate) {
        panLog.notice("rotation began")
        gestures?.rotationBegan()
    }

    func mapTemplate(
        _ mapTemplate: CPMapTemplate, didRotateWithCenter center: CGPoint, rotation: CGFloat, velocity: CGFloat
    ) {
        gestures?.rotate(rotation)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, rotationDidEndWithVelocity velocity: CGFloat) {
        gestures?.rotationEnded()
    }

    // MARK: Model → templates

    /// Updates the map template in place, and any More or Settings list on screen. Only what
    /// changed is reassigned, so nothing flickers. `dark` is CarPlay's appearance (the tiles'
    /// colours). Reads `tray.isOpen`, so a caller under observation rebuilds when it changes.
    func update(_ model: CarPlayModel, dark: Bool = true) {
        self.model = model
        gestures?.roof = model.roofKey
        let trayOpen = model.signedIn && tray.isOpen
        if !model.signedIn && tray.isOpen { tray.close() }
        if !model.signedIn, let motion, motion.mapOpen || motion.mode != .hero {
            motion.mapOpen = false
            motion.mode = .hero
        }
        let buttons = model.signedIn ? Array(model.buttons.prefix(Self.maxMapButtons)) : []
        let key = MapKey(buttons: buttons, dark: dark, trayOpen: trayOpen)
        if key != mapKey {
            mapKey = key
            if trayOpen {
                shownButtons = []
                shownApps = CarPlayModel.favouriteApps
                if !CarPlayDebug.skipMapButtons {
                    mapTemplate.mapButtons = shownApps.indices.map { appButton($0, dark: dark) }
                }
            } else {
                shownApps = []
                shownButtons = buttons
                if !CarPlayDebug.skipMapButtons {
                    mapTemplate.mapButtons = buttons.map { mapButton($0, dark: dark) }
                }
            }
        }

        let bars = BarsKey(signedIn: model.signedIn, trayOpen: trayOpen, roof: model.roofKey, dark: dark)
        if bars != barsKey {
            barsKey = bars
            setBarButtons(bars)
        }

        if let list = moreList, model.more != moreListRows {
            moreListRows = model.more
            list.updateSections(moreSections())
        }
        if let list = settingsList {
            let key = settingsKey()
            if key != settingsListKey {
                settingsListKey = key
                list.updateSections(settingsSections(key))
            }
        }
    }

    private func setBarButtons(_ key: BarsKey) {
        if CarPlayDebug.skipBarButtons { return }
        if key.signedIn {
            // In tray mode: the full grid of apps, one tap away.
            mapTemplate.leadingNavigationBarButtons = key.trayOpen
                ? [CPBarButton(title: "All apps") { [weak self] _ in self?.showApps() }]
                : []
            // Roof: the top-view Jeep for the roof it's on; a tap steps it (the strip's template path)
            let roofImage = Self.roofGlyph(key.roof, colour: key.dark ? .white : Self.ink, height: 24)
            mapTemplate.trailingNavigationBarButtons = [
                CPBarButton(image: roofImage) { [weak self] _ in self?.stepRoof() },
                barButton("ellipsis") { $0.showMore() },
            ]  // Settings lives at the bottom of More
        } else {
            mapTemplate.leadingNavigationBarButtons = []
            mapTemplate.trailingNavigationBarButtons = [
                barButton("gearshape.fill") { $0.showSettings() },
            ]
        }
    }

    // MARK: Taps

    func tap(_ kind: CarPlayButtonKind) {
        guard let button = shownButtons.first(where: { $0.kind == kind }) else { return }
        // A pending button waits for the Jeep; taps do nothing.
        guard button.state != .pending else { return }
        switch kind {
        case .lock:
            tray.close()
            // Unlock only when known locked; unknown or unlocked locks.
            perform(button.isLocked == true ? .unlock : .lock)
        case .earth:
            tray.close()
            setMap(open: !(motion?.mapOpen ?? false))
        case .jeep:
            tray.close()
            if let motion { motion.mode = motion.mode.next }
            refresh()
        case .apps:
            toggleTray()
        }
    }

    /// Opens or closes the map; the dashboard slides the Jeep over and the Earth button lights.
    func setMap(open: Bool) {
        guard let motion, motion.mapOpen != open else { return }
        motion.mapOpen = open
        motion.dividerDx = 0
        refresh()
    }

    /// The Roof bar button: Top on → Panels → Top off → Doors off → Top on; the 3D Jeep follows.
    func stepRoof() {
        guard let model, model.signedIn else { return }
        setRoof(CarPlayModel.nextRoof(after: model.roofKey))
    }

    /// Opens or closes the Apps tray; the next `update` swaps the map buttons.
    func toggleTray() {
        tray.toggle()
        refresh()
    }

    /// A favourite app on the map buttons (tray mode): opens it and closes the tray.
    func tapApp(_ index: Int) {
        guard shownApps.indices.contains(index) else { return }
        let url = shownApps[index].url
        tray.close()
        refresh()
        open(url)
    }

    /// Redraws for the state the buttons just changed (the scene rebuilds the rest under observation).
    private func refresh() {
        guard let model else { return }
        update(withMotion(model), dark: mapKey?.dark ?? true)
    }

    /// `model` with the Earth and Jeep buttons for the motion's state now.
    private func withMotion(_ model: CarPlayModel) -> CarPlayModel {
        guard let motion else { return model }
        let buttons = model.buttons.map { b -> CarPlayButton in
            switch b.kind {
            case .earth: CarPlayButton(kind: .earth, state: motion.mapOpen ? .on : .off, symbol: b.symbol, isLocked: nil)
            case .jeep: CarPlayButton(kind: .jeep, state: motion.mode == .hero ? .off : .on, symbol: b.symbol, isLocked: nil)
            default: b
            }
        }
        return CarPlayModel(
            signedIn: model.signedIn, gear: model.gear, rangeText: model.rangeText, evText: model.evText,
            chargeText: model.chargeText, tires: model.tires, tiresAgo: model.tiresAgo, roofKey: model.roofKey,
            mode: motion.mode, mapOpen: motion.mapOpen, message: model.message, buttons: buttons,
            more: model.more, apps: model.apps)
    }

    /// Does nothing if More is already on screen (no double push).
    func showMore() {
        if let list = moreList, interface.topTemplate === list { return }
        moreListRows = model?.more ?? []
        let list = CPListTemplate(title: "More", sections: moreSections())
        moreList = list
        interface.push(list)
    }

    /// The full grid, with the apps' real icons.
    func showApps() {
        let apps = model?.apps ?? CarPlayModel.appList
        let dark = mapKey?.dark ?? true
        let buttons = apps.prefix(Self.maxGridButtons).map { app in
            let image = AppIconArt.image(app, side: Self.gridIcon, circle: false, dark: dark)
            let url = app.url
            return CPGridButton(titleVariants: [app.title], image: image) { [weak self] _ in
                self?.open(url)
            }
        }
        interface.push(CPGridTemplate(title: "Apps", gridButtons: Array(buttons)))
    }

    /// Does nothing if Settings is already on screen (no double push).
    func showSettings() {
        if let list = settingsList, interface.topTemplate === list { return }
        let key = settingsKey()
        settingsListKey = key
        let list = CPListTemplate(title: "Settings", sections: settingsSections(key))
        settingsList = list
        interface.push(list)
    }

    // MARK: Lists

    private func moreSections() -> [CPListSection] {
        let items = (model?.more ?? []).map { row -> CPListItem in
            let item = CPListItem(text: row.title, detailText: row.detail)
            if let cmd = row.action {
                item.handler = { [weak self] _, completion in
                    self?.tray.close()
                    self?.perform(cmd)
                    completion()
                }
            }
            return item
        }
        let settings = CPListItem(text: "Settings", detailText: nil)
        settings.accessoryType = .disclosureIndicator
        settings.handler = { [weak self] _, completion in
            self?.showSettings()
            completion()
        }
        return [CPListSection(items: items), CPListSection(items: [settings])]
    }

    private func settingsKey() -> SettingsKey {
        let signedIn = model?.signedIn ?? false
        let mail = signedIn ? (email() ?? "") : ""
        return SettingsKey(signedIn: signedIn, email: mail.isEmpty ? CarPlayModel.dash : mail)
    }

    private func settingsSections(_ key: SettingsKey) -> [CPListSection] {
        let items: [CPListItem]
        if key.signedIn {
            items = [
                CPListItem(text: "Signed in as Milan", detailText: key.email),
                CPListItem(text: "Sign out on your iPhone", detailText: nil),
            ]
        } else {
            items = [CPListItem(text: "Sign in on your iPhone.", detailText: nil)]
        }
        // the company line, with its longhorn, at the foot of Settings
        let year = Calendar.current.component(.year, from: Date())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let company = CPListItem(
            text: "© \(year) The Neural Horn", detailText: "Forx \(version)",
            image: UIImage(named: "neural-horn")?.withTintColor(.white, renderingMode: .alwaysOriginal))
        return [CPListSection(items: items), CPListSection(items: [company])]
    }

    // MARK: Buttons

    static let gridIcon: CGFloat = 54
    static let tileSide: CGFloat = 44
    static let ink = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)

    private func mapButton(_ b: CarPlayButton, dark: Bool) -> CPMapButton {
        let kind = b.kind
        let button = CPMapButton { [weak self] _ in self?.tap(kind) }
        if kind == .jeep {
            button.image = Self.jeepTile(state: b.state, dark: dark)
        } else {
            button.image = Self.tile(symbol: b.symbol, state: b.state, dark: dark)
        }
        return button
    }

    /// A favourite app as a round map button: its real icon clipped to a circle.
    private func appButton(_ index: Int, dark: Bool) -> CPMapButton {
        let button = CPMapButton { [weak self] _ in self?.tapApp(index) }
        button.image = AppIconArt.image(shownApps[index], side: Self.tileSide, circle: true, dark: dark)
        return button
    }

    private func barButton(_ symbol: String, _ action: @escaping (CarPlayTemplates) -> Void) -> CPBarButton {
        let image = UIImage(systemName: symbol) ?? UIImage()
        return CPBarButton(image: image) { [weak self] _ in
            guard let self else { return }
            action(self)
        }
    }

    /// A 44 pt round tile, drawn at 3x; the glyph is the SF Symbol at 20 pt semibold.
    /// Night off: white on #2C2C2E with a 1 pt white 8% inner edge. Day off: #1C1C1E on white
    /// with a black 8% edge and a soft shadow. On (both): white on #0A84FF. Pending: the off
    /// tile with the glyph at 45%. Static: map button images don't animate.
    static func tile(symbol: String, state: CarPlayButtonState, dark: Bool = true) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let colour = glyphColour(state: state, dark: dark)
        let symbolImage = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(colour, renderingMode: .alwaysOriginal)
        return tile(glyph: symbolImage, state: state, dark: dark)
    }

    /// The Jeep button: Milan's front-view Jeep, 22 pt wide, on the tile (blue while a view other
    /// than the hero is up).
    static func jeepTile(state: CarPlayButtonState, dark: Bool = true) -> UIImage {
        tile(glyph: asset("jeep-front", colour: glyphColour(state: state, dark: dark), width: 22), state: state, dark: dark)
    }

    private static func glyphColour(state: CarPlayButtonState, dark: Bool) -> UIColor {
        let off = dark ? UIColor.white : ink
        switch state {
        case .off: return off
        case .on: return .white
        case .pending: return off.withAlphaComponent(0.45)
        }
    }

    /// The roof icon's asset ("roof-on", "roof-panels", "roof-off", "roof-doors"): Milan's Jeep's
    /// own top-view icons, white on clear, used as templates.
    static func roofAsset(_ roof: String) -> String {
        switch roof {
        case "panels": "roof-panels"
        case "off": "roof-off"
        case "doorsOff": "roof-doors"
        default: "roof-on"
        }
    }

    /// The top-view Jeep for `roof`, `height` pt tall, in `colour`.
    static func roofGlyph(_ roof: String, colour: UIColor, height: CGFloat = 26) -> UIImage {
        asset(roofAsset(roof), colour: colour, height: height)
    }

    /// A bundled template image drawn in `colour` at the given width or height (3x).
    static func asset(_ name: String, colour: UIColor, width: CGFloat? = nil, height: CGFloat? = nil) -> UIImage {
        guard let art = UIImage(named: name), art.size.width > 0, art.size.height > 0 else { return UIImage() }
        let size: CGSize
        if let width {
            size = CGSize(width: width, height: (art.size.height * width / art.size.width).rounded())
        } else {
            let h = height ?? 26
            size = CGSize(width: (art.size.width * h / art.size.height).rounded(), height: h)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            art.withTintColor(colour, renderingMode: .alwaysOriginal).draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
    }

    /// The round tile behind a glyph (see `tile(symbol:state:dark:)`).
    private static func tile(glyph symbolImage: UIImage?, state: CarPlayButtonState, dark: Bool) -> UIImage {
        let side = tileSide
        // day: a little room around the circle for its shadow
        let pad: CGFloat = dark ? 0 : 2
        let canvas = side + 2 * pad
        let offTile = dark ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1) : UIColor.white
        let edge = dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.08)

        let background: UIColor
        var stroke: UIColor? = edge
        var shadow = !dark
        switch state {
        case .off, .pending:
            background = offTile
        case .on:
            background = UIColor(red: 0x0A / 255, green: 0x84 / 255, blue: 1, alpha: 1)
            stroke = nil
            shadow = false
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas), format: format)
        let image = renderer.image { context in
            let circle = CGRect(x: pad, y: pad, width: side, height: side)
            let cg = context.cgContext
            if shadow {
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.12).cgColor)
                background.setFill()
                UIBezierPath(ovalIn: circle).fill()
                cg.restoreGState()
            }
            background.setFill()
            UIBezierPath(ovalIn: circle).fill()
            if let stroke {
                stroke.setStroke()
                let ring = UIBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            }
            if let symbolImage {
                let s = symbolImage.size
                symbolImage.draw(in: CGRect(
                    x: pad + (side - s.width) / 2, y: pad + (side - s.height) / 2, width: s.width, height: s.height))
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
