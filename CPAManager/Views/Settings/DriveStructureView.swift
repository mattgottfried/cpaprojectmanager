import SwiftUI

/// Settings ▸ Google ▸ Drive folders: where client folders are created, the numbered folders
/// inside each, which folder each kind of document is filed in, and how filed documents are named.
struct DriveStructureView: View {
    @AppStorage(SettingsKeys.driveClientsRootID) private var rootID = ""
    @AppStorage(SettingsKeys.driveClientsRootName) private var rootName = ""
    @AppStorage(SettingsKeys.driveAutoCreateFolders) private var autoCreate = false
    @AppStorage(SettingsKeys.driveFolderTemplate) private var templateJSON = ""

    @State private var showingPicker = false

    private var template: DriveFolderTemplate { DriveFolderTemplate.decode(templateJSON) }

    private func update(_ change: (inout DriveFolderTemplate) -> Void) {
        var copy = template
        change(&copy)
        templateJSON = copy.encoded()
    }

    private var namePreview: String {
        DocumentNaming.render(pattern: template.namePattern, title: "Engagement Letter", client: "Dana Lee", year: 2025, date: .now)
    }

    var body: some View {
        Form {
            Section {
                Button { showingPicker = true } label: {
                    HStack {
                        Label(rootID.isEmpty ? "Choose the folder for client folders…" : rootName, systemImage: "folder.fill")
                        Spacer()
                    }
                }
                Toggle("Create a client's folder automatically", isOn: $autoCreate)
                    .disabled(rootID.isEmpty)
            } header: {
                Text("Client folders")
            } footer: {
                Text("When you add a client or start a tax return, a folder named after them is created here with the folders below. An existing folder with the same name is reused, never duplicated.")
            }

            Section {
                ForEach(template.slots) { slot in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Folder name", text: Binding(
                            get: { slot.name },
                            set: { newName in update { t in
                                if let i = t.slots.firstIndex(where: { $0.id == slot.id }) { t.slots[i].name = newName }
                            } }
                        ))
                        Toggle("Year subfolders (2025, 2026…)", isOn: Binding(
                            get: { slot.yearFolders },
                            set: { on in update { t in
                                if let i = t.slots.firstIndex(where: { $0.id == slot.id }) { t.slots[i].yearFolders = on }
                            } }
                        ))
                        .font(.footnote)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { offsets in update { $0.slots.remove(atOffsets: offsets) } }
                .onMove { from, to in update { $0.slots.move(fromOffsets: from, toOffset: to) } }
                Button {
                    update { $0.slots.append(ClientFolderSlot(name: "\(String(format: "%02d", $0.slots.count)) - New folder")) }
                } label: { Label("Add folder", systemImage: "plus") }
                ForEach(template.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.color(.caution))
                }
            } header: {
                Text("Folders inside each client")
            } footer: {
                Text("Existing folders are recognised by their number, so \"02 - Source Docs\" counts as \"02 - …\" and isn't created again.")
            }

            Section {
                ForEach(DocumentKind.allCases) { kind in
                    Picker(kind.label, selection: Binding(
                        get: { template.routes[kind.rawValue] ?? "" },
                        set: { id in update { $0.routes[kind.rawValue] = id } }
                    )) {
                        Text("The client's folder itself").tag("")
                        ForEach(template.slots) { Text($0.name).tag($0.id) }
                    }
                }
            } header: {
                Text("Where documents are filed")
            } footer: {
                Text("A job with its own Drive folder always files there instead.")
            }

            Section {
                TextField("Pattern", text: Binding(
                    get: { template.namePattern },
                    set: { text in update { $0.namePattern = text } }
                ))
                .noAutocapitalization()
                LabeledContent("Example", value: namePreview)
            } header: {
                Text("File names")
            } footer: {
                Text("Use {year}, {client}, {title} and {date}. The year is the job's tax year. Empty parts drop out cleanly.")
            }

            Section {
                Button(role: .destructive) { templateJSON = "" } label: {
                    Label("Reset to the standard layout", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Drive Folders")
        .inlineNavigationTitle()
        .sheet(isPresented: $showingPicker) {
            DriveBrowserView(mode: .folder, startFolder: rootID.isEmpty ? nil : DrivePath.Crumb(id: rootID, name: rootName), onPickFolder: { crumb in
                rootID = crumb.id
                rootName = crumb.name
            })
        }
    }
}
