import CarPlay
import MapKit
import UIKit
import WidgetKit

/// The CarPlay scene: the cheapest stations nearby for the chosen fuel, with directions in Maps.
/// It only connects once the app holds the CarPlay fueling entitlement and declares the scene
/// in its Info.plist; until then the app never sees this session role.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    /// The role `AppDelegate` checks, so the shared app file needs no CarPlay import.
    static let sessionRole = UISceneSession.Role.carTemplateApplication
    /// Matches `UISceneConfigurationName` in the scene manifest.
    static let configurationName = "CarPlay"

    static func configuration(for session: UISceneSession) -> UISceneConfiguration {
        configuration(role: session.role)
    }

    static func configuration(role: UISceneSession.Role) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: configurationName, sessionRole: role)
        configuration.sceneClass = CPTemplateApplicationScene.self
        configuration.delegateClass = CarPlaySceneDelegate.self
        return configuration
    }

    private var controller: CarPlayController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        let controller = CarPlayController(scene: templateApplicationScene, interfaceController: interfaceController)
        self.controller = controller
        controller.start()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        controller?.stop()
        controller = nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        controller?.refreshIfStale()
    }
}

/// Loads the stations and keeps the car's templates in step with them.
@MainActor
final class CarPlayController {
    /// Coming back to the screen after this long fetches the prices again.
    static let staleAfter: TimeInterval = 10 * 60
    static let widgetKind = "CheapestNearby"

    private weak var scene: CPTemplateApplicationScene?
    private let interface: CPInterfaceController
    private var pointsTemplate: CPPointOfInterestTemplate?
    /// Set when the car refuses the point-of-interest template; a plain list takes over.
    private var pointsUnavailable = false
    private var loadTask: Task<Void, Never>?
    private var loadedAt: Date?

    init(scene: CPTemplateApplicationScene, interfaceController: CPInterfaceController) {
        self.scene = scene
        self.interface = interfaceController
    }

    func start() {
        showLoading(SharedSettings().fuel)
        reload()
    }

    /// Replaces whatever is on screen, so no stale stations stay up while a fetch runs.
    private func showLoading(_ fuel: FuelType) {
        pointsTemplate = nil
        setRoot(CarPlayTemplates.loading(fuel: fuel) { [weak self] in self?.showFuelPicker() })
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
    }

    func refreshIfStale(now: Date = Date()) {
        guard let loadedAt, now.timeIntervalSince(loadedAt) > Self.staleAfter else { return }
        reload()
    }

    func reload() {
        loadTask?.cancel()
        let fuel = SharedSettings().fuel
        loadTask = Task { [weak self] in
            let state = await Self.load(fuel: fuel)
            guard !Task.isCancelled, let self else { return }
            self.loadedAt = Date()
            self.render(state, fuel: fuel)
        }
    }

    /// Same source of position as the widget: a live fix, else the app's recent saved position.
    private static func load(fuel: FuelType) async -> CarPlayMapping.State {
        let settings = SharedSettings()
        let outcome = await CarPlayLocator.locate()
        guard let position = CarPlayMapping.position(for: outcome, saved: settings.lastLocation()) else {
            return CarPlayMapping.state(fuel: fuel, result: nil)
        }
        do {
            let stations = try await StationsAPI.fetchNearest(latitude: position.latitude,
                                                              longitude: position.longitude, fuel: fuel)
            return CarPlayMapping.state(fuel: fuel, result: .success(stations))
        } catch {
            return CarPlayMapping.state(fuel: fuel, result: .failure(error))
        }
    }

    private func render(_ state: CarPlayMapping.State, fuel: FuelType) {
        let title = CarPlayMapping.title(for: fuel)
        guard case .stations(let places) = state else {
            guard let template = CarPlayTemplates.information(
                for: state, retry: { [weak self] in self?.reload() },
                changeFuel: { [weak self] in self?.showFuelPicker() }) else { return }
            pointsTemplate = nil
            setRoot(template)
            return
        }

        if pointsUnavailable {
            let list = CarPlayTemplates.list(title: title, places: places) { [weak self] in self?.openDirections($0) }
            list.trailingNavigationBarButtons = [fuelButton()]
            setRoot(list)
            return
        }

        let points = places.map { CarPlayTemplates.pointOfInterest($0) { [weak self] in self?.openDirections($0) } }
        if let current = pointsTemplate, interface.rootTemplate === current {
            current.title = title
            current.setPointsOfInterest(points, selectedIndex: NSNotFound)
            return
        }
        let template = CPPointOfInterestTemplate(title: title, pointsOfInterest: points, selectedIndex: NSNotFound)
        template.trailingNavigationBarButtons = [fuelButton()]
        pointsTemplate = template
        setRoot(template) { [weak self] in
            self?.pointsUnavailable = true
            self?.pointsTemplate = nil
            self?.render(state, fuel: fuel)
        }
    }

    private func setRoot(_ template: CPTemplate, onFailure: (@MainActor () -> Void)? = nil) {
        interface.setRootTemplate(template, animated: false) { success, _ in
            guard !success, let onFailure else { return }
            Task { @MainActor in onFailure() }
        }
    }

    private func fuelButton() -> CPBarButton {
        CarPlayTemplates.fuelButton { [weak self] in self?.showFuelPicker() }
    }

    /// Two levels: the categories, then the fuels of a category (a one-fuel category selects at once).
    private func showFuelPicker() {
        let selected = SharedSettings().fuel
        let items = CarPlayMapping.categories.map { category -> CPListItem in
            let action = CarPlayMapping.pickerAction(for: category)
            let item = CPListItem(text: category.label,
                                  detailText: CarPlayMapping.categoryDetail(category, selected: selected))
            if case .showFuels = action { item.accessoryType = .disclosureIndicator }
            item.handler = { [weak self] _, completion in
                switch action {
                case .select(let fuel): self?.choose(fuel)
                case .showFuels(let fuels): self?.showFuels(fuels, title: category.label, selected: selected)
                }
                completion()
            }
            return item
        }
        push(CPListTemplate(title: CarPlayMapping.text("carplay.fuel.title"), sections: [CPListSection(items: items)]))
    }

    private func showFuels(_ fuels: [FuelType], title: String, selected: FuelType) {
        let items = fuels.map { fuel -> CPListItem in
            let item = CPListItem(text: fuel.label,
                                  detailText: fuel == selected ? CarPlayMapping.text("carplay.selected") : nil)
            item.handler = { [weak self] _, completion in
                self?.choose(fuel)
                completion()
            }
            return item
        }
        push(CPListTemplate(title: title, sections: [CPListSection(items: items)]))
    }

    private func push(_ template: CPTemplate) {
        interface.pushTemplate(template, animated: true, completion: nil)
    }

    /// The fuel is shared with the widget, so its timeline reloads too. Setting the root
    /// also drops the picker from the stack.
    private func choose(_ fuel: FuelType) {
        CarPlayMapping.choose(fuel, in: SharedSettings())
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        showLoading(fuel)
        reload()
    }

    private func openDirections(_ place: CarPlayMapping.Place) {
        CarPlayTemplates.mapItem(for: place).openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving],
            from: scene, completionHandler: { _ in })
    }
}

/// Builds the CarPlay templates from mapped values.
@MainActor
enum CarPlayTemplates {
    static func pointOfInterest(_ place: CarPlayMapping.Place,
                                directions: @escaping (CarPlayMapping.Place) -> Void) -> CPPointOfInterest {
        let point = CPPointOfInterest(location: mapItem(for: place), title: place.title, subtitle: place.subtitle,
                                      summary: place.summary, detailTitle: place.title,
                                      detailSubtitle: place.subtitle, detailSummary: place.summary, pinImage: nil)
        point.primaryButton = CPTextButton(title: CarPlayMapping.text("carplay.directions"), textStyle: .confirm) { _ in
            directions(place)
        }
        return point
    }

    /// The fallback when the point-of-interest template is not available.
    static func list(title: String, places: [CarPlayMapping.Place],
                     directions: @escaping (CarPlayMapping.Place) -> Void) -> CPListTemplate {
        let items = places.map { place -> CPListItem in
            let item = CPListItem(text: place.title, detailText: "\(place.subtitle) · \(place.summary)")
            item.handler = { _, completion in
                directions(place)
                completion()
            }
            return item
        }
        return CPListTemplate(title: title, sections: [CPListSection(items: items)])
    }

    /// The screen for a state without stations: Retry, "Change fuel" when nothing sells the fuel,
    /// and the Fuel button. `nil` for `.stations`.
    static func information(for state: CarPlayMapping.State, retry: @escaping () -> Void,
                            changeFuel: @escaping () -> Void) -> CPInformationTemplate? {
        guard let text = CarPlayMapping.message(for: state) else { return nil }
        let actions = CarPlayMapping.informationActions(for: state).map { action -> CPTextButton in
            switch action {
            case .retry: return button(CarPlayMapping.text("carplay.retry"), action: retry)
            case .changeFuel: return button(CarPlayMapping.text("carplay.changeFuel"), action: changeFuel)
            }
        }
        return information(title: text.title, message: text.message, actions: actions, changeFuel: changeFuel)
    }

    static func loading(fuel: FuelType, changeFuel: @escaping () -> Void) -> CPInformationTemplate {
        information(title: CarPlayMapping.title(for: fuel), message: CarPlayMapping.text("carplay.loading"),
                    actions: [], changeFuel: changeFuel)
    }

    /// Every information screen keeps the Fuel button, so a wrong fuel is never a dead end.
    static func information(title: String, message: String, actions: [CPTextButton],
                            changeFuel: @escaping () -> Void) -> CPInformationTemplate {
        let template = CPInformationTemplate(title: title, layout: .leading,
                                             items: [CPInformationItem(title: nil, detail: message)], actions: actions)
        template.trailingNavigationBarButtons = [fuelButton(changeFuel)]
        return template
    }

    static func fuelButton(_ action: @escaping () -> Void) -> CPBarButton {
        CPBarButton(title: CarPlayMapping.text("carplay.fuel")) { _ in action() }
    }

    static func button(_ title: String, action: @escaping () -> Void) -> CPTextButton {
        CPTextButton(title: title, textStyle: .normal) { _ in action() }
    }

    static func mapItem(for place: CarPlayMapping.Place) -> MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = place.title
        return item
    }
}
