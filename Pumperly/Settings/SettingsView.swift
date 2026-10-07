import SwiftUI
import WidgetKit

/// The one setting the widget needs: which fuel's price to show.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fuel = SharedSettings().fuel
    /// Shown the first time, before the user has confirmed a fuel.
    private let isFirstRun = !SharedSettings().hasChosenFuel

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
            .navigationTitle(Text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            // Also covers a watch app installed after the fuel was chosen.
            .onAppear { WatchSync.shared.send(fuel: fuel) }
            .onDisappear { SharedSettings().hasChosenFuel = true }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        SharedSettings().hasChosenFuel = true
                        dismiss()
                    } label: { Text("settings.done") }
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
