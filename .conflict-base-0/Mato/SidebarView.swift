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
    @State private var draggedPaneIndex: Int?
    
    var body: some View {
        Section("Panes") {
            ForEach(paneManager.panes.indices, id: \.self) { index in
                PaneRow(
                    index: index,
                    paneManager: paneManager,
                    draggedPaneIndex: $draggedPaneIndex
                )
            }
            
            Button("Add Pane") {
                paneManager.addPane()
            }
            .buttonStyle(.bordered)
            .disabled(paneManager.panes.count >= 4)
        }
    }
}

// MARK: - Pane Row (Draggable)
struct PaneRow: View {
    let index: Int
    @ObservedObject var paneManager: PaneManager
    @Binding var draggedPaneIndex: Int?
    @State private var isDropTarget = false
    
    var body: some View {
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
                    if index < paneManager.panes.count {
                        Text(paneManager.panes[index].currentDirectory?.lastPathComponent ?? "No folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .opacity(draggedPaneIndex == index ? 0.5 : 1.0)
        .background(isDropTarget ? Color.accentColor.opacity(0.2) : Color.clear)
        .draggable("pane_\(index)") {
            HStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                Text("Pane \(index + 1)")
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.8))
            .cornerRadius(6)
            .onAppear {
                draggedPaneIndex = index
            }
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedString = items.first,
                  draggedString.hasPrefix("pane_"),
                  let draggedIndex = Int(draggedString.replacingOccurrences(of: "pane_", with: "")),
                  draggedIndex != index,
                  draggedIndex < paneManager.panes.count,
                  index < paneManager.panes.count else {
                draggedPaneIndex = nil
                return false
            }
            
            paneManager.swapPanes(from: draggedIndex, to: index)
            draggedPaneIndex = nil
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
            if !targeted {
                // Reset dragged index when no longer over any target
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !isDropTarget {
                        draggedPaneIndex = nil
                    }
                }
            }
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
