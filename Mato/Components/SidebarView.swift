//
//  SidebarView.swift
//  Mato
//
//  Created by The-Ducktor on 5/24/25.
//

import SwiftUI

struct SidebarView: View {
    var paneManager: PaneManager
    var pinnedFolderStore: PinnedFolderStore
    var volumeService: VolumeService
    @Binding var showingAddPinnedFolderSheet: Bool
    
    var body: some View {
        List {
            QuickAccessSection(paneManager: paneManager)
            VolumesSection(volumeService: volumeService, paneManager: paneManager)
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
    var paneManager: PaneManager
    @State private var hoverPreloadTask: Task<Void, Never>?
    
    var body: some View {
        Section("Quick Access") {
            Button {
                paneManager.activePane?.loadDownloadsDirectory()
            } label: {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoverPreloadTask?.cancel()
                guard hovering,
                      let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                else { return }
                hoverPreloadTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    paneManager.activePane?.preloadDirectory(at: downloadsURL)
                }
            }
            
            Button {
                let homeURL = FileManager.default.homeDirectoryForCurrentUser
                paneManager.activePane?.navigate(to: homeURL)
            } label: {
                Label("Home", systemImage: "house")
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoverPreloadTask?.cancel()
                guard hovering else { return }
                let homeURL = FileManager.default.homeDirectoryForCurrentUser
                hoverPreloadTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    paneManager.activePane?.preloadDirectory(at: homeURL)
                }
            }
        }
    }
}

// MARK: - Volumes Section
struct VolumesSection: View {
    var volumeService: VolumeService
    var paneManager: PaneManager
    @State private var hoverPreloadTask: Task<Void, Never>?
    @State private var ejectingVolume: Volume?
    @State private var ejectError: String?

    var body: some View {
        Section("Devices") {
            ForEach(volumeService.volumes) { volume in
                HStack(spacing: 6) {
                    Button {
                        paneManager.activePane?.navigate(to: volume.url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: volume.icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(volume.name)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoverPreloadTask?.cancel()
                        guard hovering else { return }
                        let url = volume.url
                        hoverPreloadTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled else { return }
                            paneManager.activePane?.preloadDirectory(at: url)
                        }
                    }

                    if volume.isEjectable {
                        Button {
                            ejectVolume(volume)
                        } label: {
                            Image(systemName: "eject.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Eject “\(volume.name)”")
                        .disabled(ejectingVolume == volume)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
            }
        }
    }

    private func ejectVolume(_ volume: Volume) {
        ejectingVolume = volume
        volumeService.eject(volume)
        ejectingVolume = nil
    }
}

// MARK: - Pinned Folders Section
struct PinnedFoldersSection: View {
    var paneManager: PaneManager
    var pinnedFolderStore: PinnedFolderStore
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
    var paneManager: PaneManager
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
    var paneManager: PaneManager
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
    var paneManager: PaneManager
    var pinnedFolderStore: PinnedFolderStore
    @Binding var draggedFolderIndex: Int?
    @State private var isDropTarget = false
    @State private var showingIconPicker = false
    @State private var hoverPreloadTask: Task<Void, Never>?
    
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
                    paneManager.activePane?.navigate(to: folder.url)
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
                .onHover { hovering in
                    hoverPreloadTask?.cancel()
                    guard hovering else { return }
                    let url = folder.url
                    hoverPreloadTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        paneManager.activePane?.preloadDirectory(at: url)
                    }
                }
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
            volumeService: VolumeService(),
            showingAddPinnedFolderSheet: .constant(false)
        )
    } detail: {
        Text("Detail")
    }
}
