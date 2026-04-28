import SwiftUI

struct TagEntrySheet: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Tag")
                .font(.system(size: 17, weight: .semibold))
            TextField("Tag name", text: $appState.pendingTagText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { appState.commitPendingTag() }
            HStack {
                Spacer()
                Button("Cancel") { appState.cancelTagEditor() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { appState.commitPendingTag() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.pendingTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct CollectionPickerSheet: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to Collection")
                .font(.system(size: 17, weight: .semibold))
            if appState.collections.isEmpty {
                Text("No collections")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            } else {
                VStack(spacing: 2) {
                    ForEach(appState.collections) { collection in
                        Button {
                            appState.addPendingScreenshots(to: collection)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: collection.name == "Chemistry" ? "atom" : "folder")
                                    .frame(width: 18)
                                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                                Text(collection.name)
                                    .foregroundStyle(Theme.SemanticColor.label)
                                Spacer(minLength: 0)
                                Text("\(appState.collectionCount(forUUID: collection.uuid))")
                                    .font(.system(size: 11, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button {
                    appState.createNewCollection()
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Cancel") { appState.cancelCollectionPicker() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
