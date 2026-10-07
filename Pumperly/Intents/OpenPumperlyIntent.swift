import AppIntents

/// What "Open" opens. OpenIntent needs a target; there is one, the app itself.
enum PumperlyScreen: String, AppEnum {
    case app

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("type.screen", table: "Intents"))
    static let caseDisplayRepresentations: [PumperlyScreen: DisplayRepresentation] = [
        .app: DisplayRepresentation(title: LocalizedStringResource("screen.app", table: "Intents")),
    ]
}

/// Opens Pumperly where the user left it. It does not pick a page: the shell restores its last
/// page (ContentView's scene storage), and routing to the start page would need a hook there.
struct OpenPumperlyIntent: OpenIntent {
    static let title = LocalizedStringResource("intent.open.title", table: "Intents")
    static let description = IntentDescription(
        LocalizedStringResource("intent.open.description", table: "Intents"))

    @Parameter(title: LocalizedStringResource("param.screen", table: "Intents"), default: .app)
    var target: PumperlyScreen

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}
