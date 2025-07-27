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

    // Multiple panes management
    @StateObject private var paneManager = PaneManager()
    @State private var showingPaneSelector = false

    @StateObject private var settings = SettingsModel.shared

    var body: some View {
        NavigationSplitView {
            List {
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
                    .disabled(paneManager.panes.count >= 4) // Limit to 4 panes for UI reasons
                }
            }
            .navigationTitle("Mato")
            .sheet(isPresented: $showingAddPinnedFolderSheet) {
                AddPinnedFolderView()
            }
        } detail: {
            // Use the new PaneAreaView
            PaneAreaView(paneManager: paneManager)
                .navigationTitle(paneManager.activePane?.currentDirectory?.lastPathComponent ?? "Mato")
                .toolbar {
                    // Leading toolbar items (left side)
                    ToolbarItemGroup(placement: .navigation) {
                        // Pane indicator
                        Text("\(paneManager.activePaneIndex + 1)/\(paneManager.panes.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }

                    // Principal toolbar item (center - search)
                    ToolbarItem(placement: .principal) {
                        HStack {
                            TextField("Search", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 200, maxWidth: 400)

                            // Clear search button
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Trailing toolbar items (right side)
                    ToolbarItemGroup(placement: .primaryAction) {
                        // Layout selector
                        Menu {
                            Button {
                                paneManager.setLayout(.single)
                            } label: {
                                HStack {
                                    Text("Single Pane")
                                    Image(systemName: "rectangle")
                                    
                                }
                              
                             
                            }

                            Button {
                                paneManager.setLayout(.dual)
                                if paneManager.panes.count < 2 {
                                    paneManager.addPane()
                                }
                            } label: {
                                HStack {
                                    Text("Dual Pane")
                                    Image(systemName: "rectangle.split.2x1")
                                }
                            }

                            if paneManager.panes.count >= 3 {
                                Button {
                                    paneManager.setLayout(.triple)
                                } label: {
                                    HStack {
                                        Text("Triple Pane")
                                        Image(systemName: "rectangle.split.3x1")
                                    }
                                }
                            }

                            if paneManager.panes.count >= 4 {
                                Button {
                                    paneManager.setLayout(.quad)
                                } label: {
                                    HStack {
                                        Text("Quad Pane")
                                        Image(systemName: "rectangle.split.2x2")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: layoutIcon(for: paneManager.layout))
                        }
                        .help("Change Layout")

                        // Add pane button
                        Button {
                            paneManager.addPane()
                        } label: {
                            Image(systemName: "plus.rectangle")
                        }
                        .disabled(paneManager.panes.count >= 4)
                        .help("Add Pane")

                        // Remove active pane button
                        if paneManager.panes.count > 1 {
                            Button {
                                paneManager.removePane(at: paneManager.activePaneIndex)
                            } label: {
                                Image(systemName: "minus.rectangle")
                            }
                            .help("Close Active Pane")
                        }
                    }
                }
        }
        .onAppear {
            // Initialize panes and folder from settings
            if paneManager.panes.isEmpty {
                for _ in 0..<settings.defaultPaneCount {
                    paneManager.addPane()
                }
                paneManager.setLayout(settings.defaultPaneCount == 1 ? .single : settings.defaultPaneCount == 2 ? .dual : settings.defaultPaneCount == 3 ? .triple : .quad)
                paneManager.setActivePane(index: 0)
                let defaultURL = URL(fileURLWithPath: settings.defaultFolder)
                paneManager.panes.forEach { $0.loadDirectory(at: defaultURL) }
            }
        }
    }

    // Helper function to get the appropriate icon for each layout
    private func layoutIcon(for layout: PaneLayout) -> String {
        switch layout {
        case .single:
            return "rectangle"
        case .dual:
            return "rectangle.split.2x1"
        case .triple:
            return "rectangle.split.3x1"
        case .quad:
            return "rectangle.split.2x2"
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

// MARK: - Pane Manager
@MainActor
class PaneManager: ObservableObject {
    @Published var panes: [DirectoryViewModel] = []
    @Published var activePaneIndex: Int = 0
    @Published var layout: PaneLayout = .dual

    var activePane: DirectoryViewModel? {
        guard activePaneIndex < panes.count else { return nil }
        return panes[activePaneIndex]
    }

    init() {
        // Don't create panes in init - do it in onAppear of the view
    }

    func addPane() {
        guard panes.count < 4 else { return } // Maximum 4 panes
        let newPane = DirectoryViewModel()
        panes.append(newPane)
    }

    func removePane(at index: Int) {
        guard panes.count > 1, index < panes.count else { return }

        panes.remove(at: index)

        // Adjust active pane index
        if activePaneIndex >= panes.count {
            activePaneIndex = panes.count - 1
        } else if activePaneIndex > index {
            activePaneIndex -= 1
        }

        // Adjust layout if necessary
        if panes.count == 1 {
            layout = .single
        } else if panes.count == 2 && (layout == .triple || layout == .quad) {
            layout = .dual
        } else if panes.count == 3 && layout == .quad {
            layout = .triple
        }
    }

    func setActivePane(index: Int) {
        guard index < panes.count else { return }
        activePaneIndex = index
    }

    func setLayout(_ newLayout: PaneLayout) {
        layout = newLayout
    }
}

enum PaneLayout {
    case single
    case dual
    case triple
    case quad
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
