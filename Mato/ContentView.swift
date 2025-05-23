//
//  ContentView.swift
//  Mato
//
//  Created by  on 5/22/25.
//

import SwiftUI

struct ContentView: View {
    @State private var searchText: String = ""
    @StateObject private var directoryViewModel = DirectoryViewModel()
    @StateObject private var pinnedFolderStore = PinnedFolderStore.shared
    @State private var showingAddPinnedFolderSheet = false
    
    var body: some View {
        NavigationSplitView {
            List {
                Section("Quick Access") {
                    Button("Downloads") {
                        directoryViewModel.loadDownloadsDirectory()
                    }
                    .buttonStyle(.plain)
                    
                    Button("Home") {
                        let homeURL = FileManager.default.homeDirectoryForCurrentUser
                        directoryViewModel.loadDirectory(at: homeURL)
                        directoryViewModel.currentDirectory = homeURL
                        directoryViewModel.navigationStack = [homeURL]
                    }
                    .buttonStyle(.plain)
                }
                
                Section {
                    ForEach(pinnedFolderStore.pinnedFolders) { folder in
                        Button(folder.name) {
                            directoryViewModel.loadDirectory(at: folder.url)
                            directoryViewModel.currentDirectory = folder.url
                            directoryViewModel.navigationStack = [folder.url]
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                pinnedFolderStore.removePinnedFolder(with: folder.id)
                            }
                        }
                    }
                    
                    Button("Pin Current Folder") {
                        if let currentURL = directoryViewModel.currentDirectory {
                            pinnedFolderStore.addPinnedFolder(currentURL)
                        }
                    }
                    .disabled(directoryViewModel.currentDirectory == nil)
                    .buttonStyle(.bordered)
                } header: {
                    HStack {
                        Text("Pinned Folders")
                        Spacer()
                    }
                }
            }
            .navigationTitle("Mato")
            .sheet(isPresented: $showingAddPinnedFolderSheet) {
                AddPinnedFolderView()
            }
        } detail: {
            DirectoryView(viewModel: directoryViewModel)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 300)
                    }
                    
                    
                } .navigationTitle(directoryViewModel.currentDirectory?.lastPathComponent ?? "Mato")
        }
    }
}

struct AddPinnedFolderView: View {
    @State private var folderURL: URL?
    @State private var folderName: String = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pinnedFolderStore = PinnedFolderStore.shared
    
    var body: some View {
        VStack {
            Text("Add Pinned Folder")
                .font(.title2)
                .padding()
            
            VStack(alignment: .leading) {
                HStack {
                    Text("Folder:")
                    Spacer()
                    Button("Choose Folder") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        
                        if panel.runModal() == .OK {
                            folderURL = panel.url
                            if folderName.isEmpty {
                                folderName = folderURL?.lastPathComponent ?? ""
                            }
                        }
                    }
                }
                
                if let url = folderURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                TextField("Custom Name (Optional)", text: $folderName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical)
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add") {
                    if let url = folderURL {
                        pinnedFolderStore.addPinnedFolder(url, name: folderName.isEmpty ? nil : folderName)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderURL == nil)
            }
            .padding()
        }
        .frame(width: 400, height: 250)
    }
}

#Preview {
    ContentView()
}
