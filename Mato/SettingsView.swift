// SettingsView.swift
// Settings window UI
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsModel.shared
    @State private var folderPath: String = SettingsModel.shared.defaultFolder
    
    var body: some View {
        Form {
            Section(header: Text("Default Sort Method")) {
                Picker("Sort by", selection: $settings.defaultSortMethod) {
                    ForEach(settings.sortMethods, id: \ .self) { method in
                        Text(method.capitalized).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(header: Text("Default Folder")) {
                HStack {
                    TextField("Folder Path", text: $folderPath)
                    Button("Choose") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            folderPath = url.path
                            settings.defaultFolder = url.path
                        }
                    }
                }
                Button("Set as Default") {
                    settings.defaultFolder = folderPath
                }
            }
            Section(header: Text("Number of Panels")) {
                Stepper(value: $settings.defaultPaneCount, in: 1...4) {
                    Text("Panels: \(settings.defaultPaneCount)")
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}
