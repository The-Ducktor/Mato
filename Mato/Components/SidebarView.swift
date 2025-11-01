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
    @State private var draggedFolderIndex: Int?
    
    var body: some View {
        Section {
            ForEach(Array(pinnedFolderStore.pinnedFolders.enumerated()), id: \.element.id) { index, folder in
                PinnedFolderRow(
                    folder: folder,
                    index: index,
                    paneManager: paneManager,
                    pinnedFolderStore: pinnedFolderStore,
                    draggedFolderIndex: $draggedFolderIndex
                )
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
        VStack(spacing: 0) {
            // Insertion indicator at top
            if isDropTarget && draggedPaneIndex != nil && draggedPaneIndex! < index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.leading, 20)
                    .transition(.opacity)
            }
            
            HStack(spacing: 6) {
                Button {
                    paneManager.setActivePane(index: index)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(paneManager.activePaneIndex == index ? Color.accentColor : Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text("Pane \(index + 1)")
                        Spacer()
                        if index < paneManager.panes.count {
                            Text(paneManager.panes[index].currentDirectory?.lastPathComponent ?? "No folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDropTarget && draggedPaneIndex != nil && draggedPaneIndex! != index ?
                          Color.accentColor.opacity(0.15) : Color.clear)
            )
            .opacity(draggedPaneIndex == index ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: draggedPaneIndex == index)
            
            // Insertion indicator at bottom
            if isDropTarget && draggedPaneIndex != nil && draggedPaneIndex! > index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.leading, 20)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTarget)
        .onDrag {
            draggedPaneIndex = index
            return NSItemProvider(object: "pane_\(index)" as NSString)
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
            
            withAnimation(.easeInOut(duration: 0.25)) {
                paneManager.swapPanes(from: draggedIndex, to: index)
            }
            draggedPaneIndex = nil
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isDropTarget = targeted
            }
            if !targeted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !isDropTarget {
                        draggedPaneIndex = nil
                    }
                }
            }
        }
    }
}

// MARK: - Pinned Folder Row (Draggable)
struct PinnedFolderRow: View {
    let folder: PinnedFolder
    let index: Int
    @ObservedObject var paneManager: PaneManager
    @ObservedObject var pinnedFolderStore: PinnedFolderStore
    @Binding var draggedFolderIndex: Int?
    @State private var isDropTarget = false
    @State private var showingIconPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Insertion indicator at top
            if isDropTarget && draggedFolderIndex != nil && draggedFolderIndex! < index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.leading, 20)
                    .transition(.opacity)
            }
            
            HStack(spacing: 6) {
                Button {
                    paneManager.activePane?.loadDirectory(at: folder.url)
                    paneManager.activePane?.currentDirectory = folder.url
                    paneManager.activePane?.navigationStack = [folder.url]
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: folder.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(folder.name)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Choose Icon...") {
                        showingIconPicker = true
                    }
                    Divider()
                    Button("Remove", role: .destructive) {
                        pinnedFolderStore.removePinnedFolder(with: folder.id)
                    }
                }
                .popover(isPresented: $showingIconPicker, arrowEdge: .trailing) {
                    IconPickerView(selectedIcon: folder.icon) { newIcon in
                        pinnedFolderStore.updatePinnedFolderIcon(with: folder.id, icon: newIcon)
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDropTarget && draggedFolderIndex != nil && draggedFolderIndex! != index ?
                          Color.accentColor.opacity(0.15) : Color.clear)
            )
            .opacity(draggedFolderIndex == index ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: draggedFolderIndex == index)
            
            // Insertion indicator at bottom
            if isDropTarget && draggedFolderIndex != nil && draggedFolderIndex! > index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.leading, 20)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTarget)
        .onDrag {
            draggedFolderIndex = index
            return NSItemProvider(object: "folder_\(index)" as NSString)
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedString = items.first,
                  draggedString.hasPrefix("folder_"),
                  let draggedIndex = Int(draggedString.replacingOccurrences(of: "folder_", with: "")),
                  draggedIndex != index,
                  draggedIndex < pinnedFolderStore.pinnedFolders.count,
                  index < pinnedFolderStore.pinnedFolders.count else {
                draggedFolderIndex = nil
                return false
            }
            
            withAnimation(.easeInOut(duration: 0.25)) {
                pinnedFolderStore.movePinnedFolder(from: draggedIndex, to: index)
            }
            draggedFolderIndex = nil
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isDropTarget = targeted
            }
            if !targeted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !isDropTarget {
                        draggedFolderIndex = nil
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
