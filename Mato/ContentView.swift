//
//  ContentView.swift
//  Mato
//
//  Created by  on 5/22/25.
//

import SwiftUI

struct ContentView: View {
    @State private var searchText: String = ""
    @StateObject private var pinnedFolderStore = PinnedFolderStore.shared
    @State private var showingAddPinnedFolderSheet = false
    @StateObject private var paneManager = PaneManager()
    @StateObject private var settings = SettingsModel.shared


    var body: some View {
        NavigationSplitView {
            SidebarView(
                paneManager: paneManager,
                pinnedFolderStore: pinnedFolderStore,
                showingAddPinnedFolderSheet: $showingAddPinnedFolderSheet
            )
            .sheet(isPresented: $showingAddPinnedFolderSheet) {
                AddPinnedFolderView()
            }
        } detail: {
            PaneAreaView(paneManager: paneManager)
                .navigationTitle(paneManager.activePane?.currentDirectory?.lastPathComponent ?? "Mato")
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        PaneIndicator(
                            activeIndex: paneManager.activePaneIndex,
                            totalPanes: paneManager.panes.count
                        )
                    }

                    ToolbarItem(placement: .principal) {
                        SearchBar(searchText: $searchText)
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        ViewModeToggle(paneManager: paneManager)
                        SortMenu(paneManager: paneManager)
                        LayoutMenu(paneManager: paneManager)
                        PaneControls(paneManager: paneManager)
                    }
                }
        }
        .onAppear {
            initializePanes()
        }
    }
    
    private func initializePanes() {
        guard paneManager.panes.isEmpty else { return }
        
        let count = settings.defaultPaneCount
        let defaultURL = URL(fileURLWithPath: settings.defaultFolder)
        
        for _ in 0..<count {
            paneManager.addPane()
        }
        
        paneManager.setLayout(layoutForPaneCount(count))
        paneManager.setActivePane(index: 0)
        paneManager.panes.forEach { $0.loadDirectory(at: defaultURL) }
    }
    
    private func layoutForPaneCount(_ count: Int) -> PaneLayout {
        switch count {
        case 1: return .single
        case 2: return .dual
        case 3: return .triple
        case 4: return .quad
        default: return .dual
        }
    }
}

// MARK: - File Manager Pane Component
struct FileManagerPane: View {
    @ObservedObject var viewModel: DirectoryViewModel
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Pane header - more compact
            HStack {
                Text(viewModel.currentDirectory?.lastPathComponent ?? "No folder")
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.1) : .clear)
            .contentShape(Rectangle()) // Make the entire header tappable
            .onTapGesture {
                onActivate()
            }

            // Directory content - pass onActivate to DirectoryView
            DirectoryView(viewModel: viewModel, onActivate: onActivate)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor : .gray.opacity(0.2), lineWidth: isActive ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isActive) // Smooth focus transition
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
