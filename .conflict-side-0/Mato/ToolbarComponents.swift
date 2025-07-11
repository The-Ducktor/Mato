//
//  ToolbarComponents.swift
//  Mato
//
//  Created by The-Ducktor on 5/24/25.
//

import SwiftUI

// MARK: - Layout Menu
struct LayoutMenu: View {
    @ObservedObject var paneManager: PaneManager
    
    var body: some View {
        Menu {
            Button {
                paneManager.setLayout(.single)
            } label: {
                Label("Single Pane", systemImage: "rectangle")
            }
            
            Button {
                paneManager.setLayout(.dual)
                if paneManager.panes.count < 2 {
                    paneManager.addPane()
                }
            } label: {
                Label("Dual Pane", systemImage: "rectangle.split.2x1")
            }
            
            if paneManager.panes.count >= 3 {
                Button {
                    paneManager.setLayout(.triple)
                } label: {
                    Label("Triple Pane", systemImage: "rectangle.split.3x1")
                }
            }
            
            if paneManager.panes.count >= 4 {
                Button {
                    paneManager.setLayout(.quad)
                } label: {
                    Label("Quad Pane", systemImage: "rectangle.split.2x2")
                }
            }
        } label: {
            Image(systemName: layoutIcon(for: paneManager.layout))
        }
        .help("Change Layout")
    }
    
    private func layoutIcon(for layout: PaneLayout) -> String {
        switch layout {
        case .single: return "rectangle"
        case .dual: return "rectangle.split.2x1"
        case .triple: return "rectangle.split.3x1"
        case .quad: return "rectangle.split.2x2"
        }
    }
}

// MARK: - Pane Controls
struct PaneControls: View {
    @ObservedObject var paneManager: PaneManager
    
    var body: some View {
        Group {
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

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200, maxWidth: 400)
            
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
}

// MARK: - View Mode Toggle
struct ViewModeToggle: View {
    @ObservedObject private var settings = SettingsModel.shared
    
    var body: some View {
        Picker("View Mode", selection: $settings.viewMode) {
            Image(systemName: "list.bullet")
                .tag("list")
                .help("List View")
            Image(systemName: "square.grid.2x2")
                .tag("grid")
                .help("Grid View")
        }
        .pickerStyle(.segmented)
        .frame(width: 80)
        .help("Change View Mode")
    }
}

// MARK: - Pane Indicator
struct PaneIndicator: View {
    let activeIndex: Int
    let totalPanes: Int
    
    var body: some View {
        Text("\(activeIndex + 1)/\(totalPanes)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
