import SwiftUI

struct StationsView: View {
    @ObservedObject var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showingPicker = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.fuel.watchSymbol)
                                .foregroundStyle(Color("BrandGreen"))
                            Text(model.fuel.label)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("watch.fuel")
                    .accessibilityHint(Text("watch.changeFuel", tableName: WatchText.table))
                }
                content
            }
            .navigationTitle(Text(verbatim: "Pumperly"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPicker = true } label: {
                        Image(systemName: model.fuel.watchSymbol)
                    }
                    .accessibilityLabel(Text("watch.changeFuel", tableName: WatchText.table))
                    .accessibilityIdentifier("watch.toolbar.fuel")
                }
            }
            .sheet(isPresented: $showingPicker) {
                FuelPickerView(selected: model.fuel) { fuel in
                    model.select(fuel)
                    showingPicker = false
                }
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["PUMPERLY_UITEST_SHOW_PICKER"] == "1" { showingPicker = true }
            #endif
            model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case nil:
            HStack(spacing: 8) {
                ProgressView().frame(width: 24)
                Text("watch.loading", tableName: WatchText.table)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("watch.loading")
        case .stations(let rows):
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    StationRowView(row: row, isCheapest: index == 0)
                }
            } header: {
                Text("watch.title", tableName: WatchText.table)
            }
            refreshButton
        case .needsLocation:
            MessageRow(symbol: "location.slash", key: "watch.needsLocation")
            refreshButton
        case .empty:
            MessageRow(symbol: "fuelpump.slash", key: "watch.empty")
            refreshButton
        case .unavailable:
            MessageRow(symbol: "wifi.exclamationmark", key: "watch.offline")
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button { model.refresh(force: true) } label: {
            HStack {
                Spacer()
                if model.isLoading {
                    ProgressView().frame(width: 20, height: 20)
                } else {
                    Label {
                        Text(LocalizedStringKey(isMessage ? "watch.retry" : "watch.refresh"),
                             tableName: WatchText.table)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                Spacer()
            }
        }
        .disabled(model.isLoading)
        .accessibilityIdentifier("watch.refresh")
    }

    private var isMessage: Bool {
        if case .stations = model.content { return false }
        return true
    }
}

private struct StationRowView: View {
    let row: StationRow
    let isCheapest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.valueText ?? "—")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(isCheapest ? Color("BrandGreen") : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(row.distanceText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(row.name)
                .font(.footnote)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MessageRow: View {
    let symbol: String
    let key: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(WatchText.string(key))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(key)
    }
}

struct FuelPickerView: View {
    let selected: FuelType
    let onSelect: (FuelType) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(FuelType.Category.allCases) { category in
                    Section(category.label) {
                        ForEach(category.fuels) { fuel in
                            Button { onSelect(fuel) } label: {
                                HStack {
                                    Text(fuel.label)
                                    Spacer(minLength: 4)
                                    if fuel == selected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color("BrandGreen"))
                                    }
                                }
                            }
                            .accessibilityIdentifier("watch.fuel.\(fuel.rawValue)")
                            .accessibilityAddTraits(fuel == selected ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(Text("watch.fuel", tableName: WatchText.table))
        }
    }
}
