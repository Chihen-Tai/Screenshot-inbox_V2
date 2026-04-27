import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SidebarViewModel()

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            Section {
                ForEach(viewModel.library) { item in
                    SidebarItemView(item: item)
                }
            } header: {
                SidebarSectionView(title: "Library")
            }

            Section {
                ForEach(viewModel.collections) { item in
                    SidebarItemView(item: item)
                }
            } header: {
                SidebarSectionView(title: "Collections")
            }

            Section {
                ForEach(viewModel.smart) { item in
                    SidebarItemView(item: item)
                }
            } header: {
                SidebarSectionView(title: "Smart Collections")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            settingsRow
        }
        .navigationSplitViewColumnWidth(
            min: Theme.Layout.sidebarMin,
            ideal: Theme.Layout.sidebarIdeal,
            max: Theme.Layout.sidebarMax
        )
    }

    private var settingsRow: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Button {
                appState.sidebarSelection = .settings
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.settingsItem.systemImage)
                        .font(.system(size: 13))
                        .frame(width: 20)
                        .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    Text(viewModel.settingsItem.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.SemanticColor.label)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Layout.sidebarRowHPadding)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(appState.sidebarSelection == .settings
                              ? Theme.Palette.selectionFill
                              : .clear)
                        .padding(.horizontal, Theme.Layout.sidebarHorizontalInset)
                )
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
    }
}
