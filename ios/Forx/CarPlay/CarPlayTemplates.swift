import CarPlay
import UIKit

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

/// The CarPlay templates: one map template whose buttons are updated in place, plus the
/// More list, the Apps grid and Settings, pushed on tap.
@MainActor
final class CarPlayTemplates {
    let mapTemplate = CPMapTemplate()
    /// The map buttons now shown, left to right (mirrors `mapTemplate.mapButtons`).
    private(set) var shownButtons: [CarPlayButton] = []

    private let interface: any CarPlayInterface
    private let open: (URL) -> Void
    private let perform: (JeepCommand) -> Void
    private let setRoof: (String) -> Void
    private let email: () -> String?
    private var model: CarPlayModel?
    /// What the bar buttons were last built for (nil: not yet).
    private var barsSignedIn: Bool?
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
        email: @escaping () -> String? = { AppModel.store.email }
    ) {
        self.interface = interface
        self.open = open
        self.perform = perform
        self.setRoof = setRoof
        self.email = email
        mapTemplate.automaticallyHidesNavigationBar = false
        interface.setRoot(mapTemplate)
    }

    // MARK: Model → templates

    /// Updates the map template in place, and any More or Settings list on screen. Only what
    /// changed is reassigned, so nothing flickers.
    func update(_ model: CarPlayModel) {
        self.model = model
        let buttons = model.signedIn ? Array(model.buttons.prefix(Self.maxMapButtons)) : []
        if buttons != shownButtons {
            shownButtons = buttons
            mapTemplate.mapButtons = buttons.map(mapButton)
        }

        if model.signedIn != barsSignedIn {
            barsSignedIn = model.signedIn
            setBarButtons(signedIn: model.signedIn)
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

    private func setBarButtons(signedIn: Bool) {
        if signedIn {
            mapTemplate.leadingNavigationBarButtons = [
                barButton("magnifyingglass") { $0.tapSearch() },
            ]
            mapTemplate.trailingNavigationBarButtons = [
                barButton("square.grid.3x3.fill") { $0.showApps() },
                barButton("gearshape.fill") { $0.showSettings() },
            ]
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
            // Unlock only when known locked; unknown or unlocked locks.
            perform(button.isLocked == true ? .unlock : .lock)
        case .climate:
            perform(button.state == .on ? .climateOff : .climateOn)
        case .lights:
            perform(.lights)
        case .more:
            showMore()
        }
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

    func showApps() {
        let apps = model?.apps ?? CarPlayModel.appList
        let buttons = apps.prefix(Self.maxGridButtons).map { app in
            let image = (UIImage(systemName: app.symbol) ?? UIImage())
                .withTintColor(.white, renderingMode: .alwaysOriginal)
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
                    self?.perform(cmd)
                    completion()
                }
            }
            return item
        }
        return [CPListSection(items: items)]
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

    private func mapButton(_ b: CarPlayButton) -> CPMapButton {
        let kind = b.kind
        let button = CPMapButton { [weak self] _ in self?.tap(kind) }
        button.image = Self.tile(symbol: b.symbol, state: b.state)
        return button
    }

    private func barButton(_ symbol: String, _ action: @escaping (CarPlayTemplates) -> Void) -> CPBarButton {
        let image = UIImage(systemName: symbol) ?? UIImage()
        return CPBarButton(image: image) { [weak self] _ in
            guard let self else { return }
            action(self)
        }
    }

    /// A 44 pt round tile. Off: white glyph on #1C1C1E. On: black glyph on #F5F5F7.
    /// Pending: 50% white glyph on #1C1C1E. Static: map button images don't animate.
    static func tile(symbol: String, state: CarPlayButtonState) -> UIImage {
        let side: CGFloat = 44
        let background: UIColor
        let glyph: UIColor
        switch state {
        case .off:
            background = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
            glyph = .white
        case .on:
            background = UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
            glyph = .black
        case .pending:
            background = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
            glyph = UIColor.white.withAlphaComponent(0.5)
        }
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let symbolImage = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(glyph, renderingMode: .alwaysOriginal)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            background.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            if let symbolImage {
                let s = symbolImage.size
                symbolImage.draw(in: CGRect(
                    x: (side - s.width) / 2, y: (side - s.height) / 2, width: s.width, height: s.height))
            }
        }
    }
}
