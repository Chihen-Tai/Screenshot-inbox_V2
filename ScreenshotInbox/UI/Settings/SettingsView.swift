import SwiftUI

/// Root of the Settings scene. Three calm tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "externaldrive") }
            ImportSourceSettingsView()
                .tabItem { Label("Import", systemImage: "tray.and.arrow.down") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 560, height: 420)
    }
}
