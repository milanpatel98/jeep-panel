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
    static var demo: Bool { mode == "demo" }

    /// The demo Jeep (`FORX_CP=demo`, Debug only): nil otherwise.
    static func demoSnapshot(now: Date = Date()) -> JeepSnapshot? {
        #if DEBUG
        guard demo else { return nil }
        return JeepSnapshot(
            nickname: "Jeep", locked: true, doorsOpen: [], tailgateOpen: false,
            rangeMiles: 186, fuelPercent: 64, evPercent: 78, pluggedIn: false, charging: false,
            chargeMinutesLeft: nil, tiresPsi: ["FL": 36, "FR": 36, "RL": 35, "RR": 36],
            odometerMiles: nil, latitude: 39.7555, longitude: -105.2211,
            supported: [.lock, .unlock, .climateOn, .climateOff, .lights, .horn],
            updatedAt: now, ignitionOn: false, gasRangeMiles: 165)
        #else
        return nil
        #endif
    }
}

/// The CarPlay templates: one map template whose buttons are updated in place, plus the
/// More list, the Apps grid and Settings, pushed on tap. The Apps button opens the tray: the
/// map buttons become the four favourite apps until one opens, a command runs, or 8 s pass.
/// Sideways drags on the map turn the 3D Jeep (`spin`); the Roof button steps the roof.
@MainActor
final class CarPlayTemplates: NSObject, CPMapTemplateDelegate {
    let mapTemplate = CPMapTemplate()
    /// The map buttons now shown, left to right (mirrors `mapTemplate.mapButtons`); empty while
    /// the tray shows its apps instead.
    private(set) var shownButtons: [CarPlayButton] = []
    /// The apps on the map buttons while the tray is open.
    private(set) var shownApps: [CarPlayApp] = []
    let tray: AppTray
    let spin: DashboardSpin?
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

    init(
        interface: any CarPlayInterface,
        open: @escaping (URL) -> Void,
        perform: @escaping (JeepCommand) -> Void,
        setRoof: @escaping (String) -> Void = { AppModel.roof = $0 },
        email: @escaping () -> String? = { AppModel.store.email },
        tray: AppTray = AppTray(),
        spin: DashboardSpin? = nil
    ) {
        self.interface = interface
        self.open = open
        self.perform = perform
        self.tray = tray
        self.spin = spin
        self.setRoof = setRoof
        self.email = email
        super.init()
        // The host's view controller (share button, etc.) talks to the delegate; without one
        // it crashes CarPlayTemplateUIHost. Set before the template becomes root.
        if !CarPlayDebug.skipMapDelegate { mapTemplate.mapDelegate = self }
        // Search and Apps fade away when the screen isn't touched (the cards then take the full
        // height) and come back on any touch. The map buttons stay.
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

    // MARK: Drags → 3D Jeep

    /// CarPlay sends these on touch screens without panning mode; the map never pans.
    func mapTemplateDidBeginPanGesture(_ mapTemplate: CPMapTemplate) {
        panLog.notice("pan began")
        spin?.began()
    }

    func mapTemplate(
        _ mapTemplate: CPMapTemplate, didUpdatePanGestureWithTranslation translation: CGPoint, velocity: CGPoint
    ) {
        spin?.changed(translation)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, didEndPanGestureWithVelocity velocity: CGPoint) {
        panLog.notice("pan ended")
        spin?.ended(velocity)
    }

    // MARK: Model → templates

    /// Updates the map template in place, and any More or Settings list on screen. Only what
    /// changed is reassigned, so nothing flickers. `dark` is CarPlay's appearance (the tiles'
    /// colours). Reads `tray.isOpen`, so a caller under observation rebuilds when it changes.
    func update(_ model: CarPlayModel, dark: Bool = true) {
        self.model = model
        let trayOpen = model.signedIn && tray.isOpen
        if !model.signedIn && tray.isOpen { tray.close() }
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

        let bars = BarsKey(signedIn: model.signedIn, trayOpen: trayOpen)
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
            var leading = [barButton("magnifyingglass") { $0.tapSearch() }]
            // In tray mode: the full grid of apps, one tap away.
            if key.trayOpen {
                leading.append(CPBarButton(title: "All apps") { [weak self] _ in self?.showApps() })
            }
            mapTemplate.leadingNavigationBarButtons = leading
            mapTemplate.trailingNavigationBarButtons = [
                // filled while the tray is open
                barButton(key.trayOpen ? "square.grid.3x3.fill" : "square.grid.3x3") { $0.toggleTray() },
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
        tray.close()
        switch kind {
        case .lock:
            // Unlock only when known locked; unknown or unlocked locks.
            perform(button.isLocked == true ? .unlock : .lock)
        case .climate:
            perform(button.state == .on ? .climateOff : .climateOn)
        case .roof:
            // Top on → Panels → Top off → Doors off → Top on; the 3D Jeep follows the roof.
            setRoof(CarPlayModel.nextRoof(after: button.roof ?? "on"))
        case .more:
            showMore()
        }
    }

    /// Opens or closes the Apps tray; the next `update` swaps the map buttons.
    func toggleTray() {
        tray.toggle()
        if let model { update(model, dark: mapKey?.dark ?? true) }
    }

    /// A favourite app on the map buttons (tray mode): opens it and closes the tray.
    func tapApp(_ index: Int) {
        guard shownApps.indices.contains(index) else { return }
        let url = shownApps[index].url
        tray.close()
        if let model { update(model, dark: mapKey?.dark ?? true) }
        open(url)
    }

    func tapSearch() {
        open(URL(string: "maps://")!)
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
            if let key = row.roofKey {
                item.handler = { [weak self] _, completion in
                    self?.setRoof(key)
                    completion()
                }
            } else if let cmd = row.action {
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
        return [CPListSection(items: items)]
    }

    // MARK: Buttons

    static let gridIcon: CGFloat = 54
    static let tileSide: CGFloat = 44

    private func mapButton(_ b: CarPlayButton, dark: Bool) -> CPMapButton {
        let kind = b.kind
        let button = CPMapButton { [weak self] _ in self?.tap(kind) }
        if kind == .roof {
            button.image = Self.roofTile(b.roof ?? "on", dark: dark)
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

    /// The Roof button: the off tile (it's a mode, not on/off) with a drawn top-view Jeep for `roof`.
    static func roofTile(_ roof: String, dark: Bool = true) -> UIImage {
        tile(glyph: roofGlyph(roof, colour: glyphColour(state: .off, dark: dark)), state: .off, dark: dark)
    }

    private static func glyphColour(state: CarPlayButtonState, dark: Bool) -> UIColor {
        let ink = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
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

    /// The top-view Jeep for `roof`, 26 pt tall, in `colour`.
    static func roofGlyph(_ roof: String, colour: UIColor, height: CGFloat = 26) -> UIImage {
        guard let art = UIImage(named: roofAsset(roof)) else { return UIImage() }
        let size = CGSize(width: (art.size.width * height / max(1, art.size.height)).rounded(), height: height)
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
