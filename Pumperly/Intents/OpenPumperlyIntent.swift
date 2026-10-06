import AppIntents

/// The screens an intent can open. The app is the route planner, so there is one.
enum PumperlyScreen: String, AppEnum {
    case planner

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("type.screen", table: "Intents"))
    static let caseDisplayRepresentations: [PumperlyScreen: DisplayRepresentation] = [
        .planner: DisplayRepresentation(title: LocalizedStringResource("screen.planner", table: "Intents")),
    ]
}

/// Opens the app on the route planner.
struct OpenPumperlyIntent: OpenIntent {
    static let title = LocalizedStringResource("intent.open.title", table: "Intents")
    static let description = IntentDescription(
        LocalizedStringResource("intent.open.description", table: "Intents"))

    @Parameter(title: LocalizedStringResource("param.screen", table: "Intents"), default: .planner)
    var target: PumperlyScreen

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}
