import SwiftUI

/// Root of the Settings scene.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "externaldrive") }
            ImportSourceSettingsView()
                .tabItem { Label("Auto Import", systemImage: "tray.and.arrow.down") }
            OrganizationRulesSettingsView()
                .tabItem { Label("Rules", systemImage: "wand.and.stars") }
            RenameSettingsView()
                .tabItem { Label("Rename", systemImage: "pencil") }
            OCRSettingsView()
                .tabItem { Label("OCR", systemImage: "text.viewfinder") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            #if DEBUG
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            #endif
        }
        .frame(width: 640, height: 480)
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
