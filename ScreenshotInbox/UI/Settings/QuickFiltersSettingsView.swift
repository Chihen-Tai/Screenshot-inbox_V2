import SwiftUI

struct QuickFiltersSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "Quick Filters") {
                    SettingsNote(text: "Choose which built-in filters appear above the grid. The chip row stays focused on quick use; management lives here.")

                    VStack(spacing: 0) {
                        ForEach(appState.preferences.quickFilters) { filter in
                            quickFilterRow(filter)
                            if appState.preferences.quickFilters.last.map({ filter != $0 }) ?? false {
                                Divider().padding(.leading, 30)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                            .fill(Theme.SemanticColor.panel.opacity(0.45))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))

                    Button("Reset to Defaults") {
                        appState.resetQuickFiltersToDefaults()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
    }

    private func quickFilterRow(_ filter: QuickFilterPreference) -> some View {
        HStack(spacing: 10) {
            Toggle(filter.chip.rawValue, isOn: binding(for: filter.chip))
                .toggleStyle(.checkbox)
            Spacer(minLength: 12)
            Button {
                appState.moveQuickFilterUp(filter)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Move Up")
            .disabled(filter == appState.preferences.quickFilters.first)

            Button {
                appState.moveQuickFilterDown(filter)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Move Down")
            .disabled(filter == appState.preferences.quickFilters.last)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func binding(for chip: FilterChip) -> Binding<Bool> {
        Binding(
            get: {
                appState.preferences.quickFilters.first { $0.chip == chip }?.isEnabled ?? false
            },
            set: { isEnabled in
                guard let index = appState.preferences.quickFilters.firstIndex(where: { $0.chip == chip }) else { return }
                appState.preferences.quickFilters[index].isEnabled = isEnabled
            }
        )
    }
}
