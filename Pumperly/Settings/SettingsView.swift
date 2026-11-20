import SwiftUI
import WidgetKit

/// The user's fuel: the map, the widget, Siri and the watch use it.
/// The first time it asks for it, with nothing picked, and the map opens on the answer.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Shown the first time, before the user has confirmed a fuel. State, so it holds while the sheet is up.
    @State private var isFirstRun = !SharedSettings().hasChosenFuel
    /// Nil on the first run until the user taps a fuel: the app never picks one for them.
    @State private var fuel: FuelType? = SharedSettings().hasChosenFuel ? SharedSettings().fuel : nil
    /// Called once when the first-run sheet closes with a fuel, so the map can open on it.
    var onFirstRunChoice: (FuelType) -> Void = { _ in }
    /// Called when the sheet closes on a later run, so the map can reload on a changed fuel.
    var onClose: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isFirstRun {
                        Text("settings.intro")
                            .font(.subheadline)
                            .accessibilityIdentifier("settings.intro")
                    }
                    Text("settings.fuel.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(FuelType.Category.allCases) { category in
                    Section(category.label) {
                        ForEach(category.fuels) { option in
                            Button {
                                select(option)
                            } label: {
                                HStack {
                                    Text(option.label).foregroundStyle(Color.primary)
                                    Spacer()
                                    if option == fuel {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Color("BrandGreen"))
                                    }
                                }
                            }
                            .accessibilityIdentifier("settings.fuel.\(option.rawValue)")
                            .accessibilityAddTraits(option == fuel ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(Text(isFirstRun ? "settings.title.firstRun" : "settings.fuel"))
            .navigationBarTitleDisplayMode(.inline)
            // No swipe-down past the first question until a fuel is picked.
            .interactiveDismissDisabled(fuel == nil)
            // Also covers a watch app installed after the fuel was chosen.
            .onAppear { if let fuel { WatchSync.shared.send(fuel: fuel) } }
            .onDisappear {
                guard let fuel else { return }
                SharedSettings().hasChosenFuel = true
                if isFirstRun { onFirstRunChoice(fuel) } else { onClose() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: { Text("settings.done") }
                        .disabled(fuel == nil)
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    private func select(_ option: FuelType) {
        guard option != fuel else { return }
        fuel = option
        SharedSettings().fuel = option
        SharedSettings().hasChosenFuel = true
        WidgetCenter.shared.reloadTimelines(ofKind: "CheapestNearby")
        WatchSync.shared.send(fuel: option)
    }
}
