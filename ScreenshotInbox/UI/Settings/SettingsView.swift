import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable {
    case general = "General"
    case library = "Library"
    case autoImport = "Auto Import"
    case privacy = "Privacy"
    case rules = "Rules"
    case rename = "Rename"
    case ocr = "OCR"
    case appearance = "Appearance"
    case quickFilters = "Quick Filters"
    case advanced = "Advanced"

    static var available: [SettingsTab] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter { $0 != .advanced }
        #endif
    }
}

/// Root of the Settings scene.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab

    init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings Section", selection: $selectedTab) {
                ForEach(SettingsTab.available, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .library:
                    LibrarySettingsView()
                case .autoImport:
                    ImportSourceSettingsView()
                case .privacy:
                    PrivacySettingsView()
                case .rules:
                    OrganizationRulesSettingsView()
                case .rename:
                    RenameSettingsView()
                case .ocr:
                    OCRSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .quickFilters:
                    QuickFiltersSettingsView()
                case .advanced:
                    #if DEBUG
                    AdvancedSettingsView()
                    #else
                    EmptyView()
                    #endif
                }
            }
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 520, idealHeight: 620)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.SemanticColor.quietFill.opacity(0.35))
        )
    }
}

struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
    }
}
