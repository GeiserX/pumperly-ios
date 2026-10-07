import AppIntents

/// `FuelType` as Siri and Shortcuts see it. The raw values are the API codes, identical to
/// `FuelType`'s, and the titles reuse its strings (`fuel.<code>` in Localizable.strings), so
/// both the round trip and the names match the app and the widget.
enum FuelChoice: String, AppEnum {
    case b7 = "B7"
    case b7Premium = "B7_PREMIUM"
    case b10 = "B10"
    case bAgricultural = "B_AGRICULTURAL"
    case hvo = "HVO"
    case e5 = "E5"
    case e5Premium = "E5_PREMIUM"
    case e10 = "E10"
    case e5_98 = "E5_98"
    case e98E10 = "E98_E10"
    case lpg = "LPG"
    case cng = "CNG"
    case lng = "LNG"
    case h2 = "H2"
    case ev = "EV"
    case adblue = "ADBLUE"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("type.fuel", table: "Intents"))

    // App Intents reads these at build time, so they must be literals, not `FuelType.label`.
    static let caseDisplayRepresentations: [FuelChoice: DisplayRepresentation] = [
        .b7: DisplayRepresentation(title: "fuel.B7"),
        .b7Premium: DisplayRepresentation(title: "fuel.B7_PREMIUM"),
        .b10: DisplayRepresentation(title: "fuel.B10"),
        .bAgricultural: DisplayRepresentation(title: "fuel.B_AGRICULTURAL"),
        .hvo: DisplayRepresentation(title: "fuel.HVO"),
        .e5: DisplayRepresentation(title: "fuel.E5"),
        .e5Premium: DisplayRepresentation(title: "fuel.E5_PREMIUM"),
        .e10: DisplayRepresentation(title: "fuel.E10"),
        .e5_98: DisplayRepresentation(title: "fuel.E5_98"),
        .e98E10: DisplayRepresentation(title: "fuel.E98_E10"),
        .lpg: DisplayRepresentation(title: "fuel.LPG"),
        .cng: DisplayRepresentation(title: "fuel.CNG"),
        .lng: DisplayRepresentation(title: "fuel.LNG"),
        .h2: DisplayRepresentation(title: "fuel.H2"),
        .ev: DisplayRepresentation(title: "fuel.EV"),
        .adblue: DisplayRepresentation(title: "fuel.ADBLUE"),
    ]

    init(_ fuel: FuelType) {
        // Every FuelType has a case here; IntentsTests checks it.
        self = FuelChoice(rawValue: fuel.rawValue)!
    }

    var fuel: FuelType {
        FuelType(rawValue: rawValue)!
    }
}
