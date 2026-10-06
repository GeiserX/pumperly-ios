import AppIntents

/// Siri phrases and Spotlight shortcuts. The English phrases are the keys of AppShortcuts.strings;
/// every phrase must name the app.
struct PumperlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheapestNearbyIntent(),
            phrases: [
                "Cheapest fuel nearby in \(.applicationName)",
                "Find the cheapest fuel with \(.applicationName)",
                "Cheapest \(\.$fuel) nearby in \(.applicationName)",
                "Where is the cheapest \(\.$fuel) in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("shortcut.cheapest", table: "Intents"),
            systemImageName: "fuelpump.fill")
        AppShortcut(
            intent: SetWidgetFuelIntent(),
            phrases: [
                "Set the widget fuel in \(.applicationName)",
                "Show \(\.$fuel) in the \(.applicationName) widget",
            ],
            shortTitle: LocalizedStringResource("shortcut.setFuel", table: "Intents"),
            systemImageName: "slider.horizontal.3")
        AppShortcut(
            intent: OpenPumperlyIntent(),
            phrases: [
                "Plan a route with \(.applicationName)",
                "Open the planner in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("shortcut.open", table: "Intents"),
            systemImageName: "map")
    }

    static let shortcutTileColor: ShortcutTileColor = .lime
}
