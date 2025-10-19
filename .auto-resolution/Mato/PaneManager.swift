//
//  PaneManager.swift
//  Mato
//
//  Created by The-Ducktor on 5/24/25.
//

import Foundation
import SwiftUI

// MARK: - Pane Layout
enum PaneLayout: Codable {
    case single
    case dual
    case triple
    case quad
}

// MARK: - Pane Manager
@MainActor
class PaneManager: ObservableObject {
    @Published var panes: [DirectoryViewModel] = []
    @Published var activePaneIndex: Int = 0
    @Published var layout: PaneLayout = .dual
    
    var paneCount: Int { panes.count }
    
    var activePane: DirectoryViewModel? {
        guard activePaneIndex >= 0, activePaneIndex < panes.count else { return nil }
        return panes[activePaneIndex]
    }
    
    init() {
        // Start with 0, populate onAppear or via reset()
    }
    
    /// Reset all panes with a given count and optional folder (default: settings)
    func reset(withCount count: Int, folder: URL? = nil) {
        let folderURL = folder ?? SettingsModel.shared.defaultFolderURL
        panes = (0..<count).map { _ in
            let vm = DirectoryViewModel()
            vm.loadDirectory(at: folderURL)
            return vm
        }
        activePaneIndex = 0
        syncLayoutWithPaneCount()
    }
    
    func addPane(folder: URL? = nil) {
        guard panes.count < 4 else { return }
        let vm = DirectoryViewModel()
        if let url = folder ?? SettingsModel.shared.defaultFolderURL as URL? {
            vm.loadDirectory(at: url)
        }
        panes.append(vm)
        if panes.count == 1 { activePaneIndex = 0 }
        syncLayoutWithPaneCount()
    }
    
    func removePane(at index: Int) {
        guard panes.count > 1, index >= 0, index < panes.count else { return }
        panes.remove(at: index)
        if activePaneIndex >= panes.count {
            activePaneIndex = max(0, panes.count - 1)
        }
        syncLayoutWithPaneCount()
    }
    
    func setActivePane(index: Int) {
        guard index >= 0, index < panes.count else { return }
        activePaneIndex = index
    }
    
    func setLayout(_ newLayout: PaneLayout) {
        layout = newLayout
    }
    
    private func syncLayoutWithPaneCount() {
        switch panes.count {
        case 1: layout = .single
        case 2: layout = .dual
        case 3: layout = .triple
        case 4: layout = .quad
        default: layout = .dual
        }
    }
}
