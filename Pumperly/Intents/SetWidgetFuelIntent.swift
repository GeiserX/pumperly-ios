import AppIntents
import WidgetKit

/// Sets the fuel the Cheapest nearby widget shows, as the settings screen does.
struct SetWidgetFuelIntent: AppIntent {
    static let title = LocalizedStringResource("intent.setFuel.title", table: "Intents")
    static let description = IntentDescription(
        LocalizedStringResource("intent.setFuel.description", table: "Intents"))

    @Parameter(title: LocalizedStringResource("param.fuel", table: "Intents"))
    var fuel: FuelChoice

    init() {}

    init(fuel: FuelChoice) {
        self.fuel = fuel
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        apply(to: SharedSettings(), reload: { WidgetCenter.shared.reloadAllTimelines() })
        return .result(dialog: IntentDialog(stringLiteral: Self.dialog(for: fuel.fuel)))
    }

    /// Writes the fuel and the "chosen" flag, then refreshes the widgets. Split out for tests.
    func apply(to settings: SharedSettings, reload: () -> Void) {
        settings.fuel = fuel.fuel
        settings.hasChosenFuel = true
        reload()
    }

    static func dialog(for fuel: FuelType, bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: "dialog.setFuel", value: nil, table: "Intents"), fuel.label)
    }
}
