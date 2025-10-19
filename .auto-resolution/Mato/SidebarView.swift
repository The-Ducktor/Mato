//
//  SidebarView.swift
//  Mato
//
//  Created by The-Ducktor on 5/24/25.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var paneManager: PaneManager
    @ObservedObject var pinnedFolderStore: PinnedFolderStore
    @Binding var showingAddPinnedFolderSheet: Bool
    
    var body: some View {
        List {
            QuickAccessSection(paneManager: paneManager)
            PinnedFoldersSection(
                paneManager: paneManager,
                pinnedFolderStore: pinnedFolderStore
            )
            PanesSection(paneManager: paneManager)
        }
        .navigationTitle("Mato")
    }
}

// MARK: - Quick Access Section
struct QuickAccessSection: View {
    @ObservedObject var paneManager: PaneManager
    
    var body: some View {
        Section("Quick Access") {
            Button {
                paneManager.activePane?.loadDownloadsDirectory()
            } label: {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            
            Button {
                let homeURL = FileManager.default.homeDirectoryForCurrentUser
                paneManager.activePane?.loadDirectory(at: homeURL)
                paneManager.activePane?.currentDirectory = homeURL
                paneManager.activePane?.navigationStack = [homeURL]
            } label: {
                Label("Home", systemImage: "house")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Pinned Folders Section
struct PinnedFoldersSection: View {
    @ObservedObject var paneManager: PaneManager
    @ObservedObject var pinnedFolderStore: PinnedFolderStore
    
    var body: some View {
        Section {
            ForEach(pinnedFolderStore.pinnedFolders) { folder in
                Button {
                    paneManager.activePane?.loadDirectory(at: folder.url)
                    paneManager.activePane?.currentDirectory = folder.url
                    paneManager.activePane?.navigationStack = [folder.url]
                } label: {
                    Label(folder.name, systemImage: "folder")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove", role: .destructive) {
                        pinnedFolderStore.removePinnedFolder(with: folder.id)
                    }
                }
            }
            
            Button("Pin Current Folder") {
                if let currentURL = paneManager.activePane?.currentDirectory {
                    pinnedFolderStore.addPinnedFolder(currentURL)
                }
            }
            .disabled(paneManager.activePane?.currentDirectory == nil)
            .buttonStyle(.bordered)
        } header: {
            HStack {
                Text("Pinned Folders")
                Spacer()
            }
        }
    }
}

// MARK: - Panes Section
struct PanesSection: View {
    @ObservedObject var paneManager: PaneManager
    
    var body: some View {
        Section("Panes") {
            ForEach(paneManager.panes.indices, id: \.self) { index in
                HStack {
                    Button {
                        paneManager.setActivePane(index: index)
                    } label: {
                        HStack {
                            Circle()
                                .fill(paneManager.activePaneIndex == index ? Color.accentColor : .gray)
                                .frame(width: 8, height: 8)
                            Text("Pane \(index + 1)")
                            Spacer()
                            Text(paneManager.panes[index].currentDirectory?.lastPathComponent ?? "No folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if paneManager.panes.count > 1 {
                        Button {
                            paneManager.removePane(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button("Add Pane") {
                paneManager.addPane()
            }
            .buttonStyle(.bordered)
            .disabled(paneManager.panes.count >= 4)
        }
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(
            paneManager: PaneManager(),
            pinnedFolderStore: PinnedFolderStore.shared,
            showingAddPinnedFolderSheet: .constant(false)
        )
    } detail: {
        Text("Detail")
    }
}
