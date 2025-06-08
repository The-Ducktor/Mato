//
//  PathBar.swift
//  Mato
//
//  Created by  on 5/22/25.
//

import SwiftUI

struct PathBar: View {
    @State private var isEditing = false
    @State private var pathString: String
    @ObservedObject var viewModel: DirectoryViewModel
    @State var path: URL
    @FocusState private var isTextFieldFocused: Bool
    
    init(path: URL, viewModel: DirectoryViewModel) {
        self.path = path
        self._pathString = State(initialValue: path.path)
        self.viewModel = viewModel
    }
    
    var body: some View {
        Group {
            if isEditing {
                editingView
            } else {
                breadcrumbView
            }
        }.padding(.horizontal, 10) // Reduced horizontal padding to accommodate navigation buttons
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEditing)
        .onChange(of: viewModel.currentDirectory) {
            if let directory = viewModel.currentDirectory {
                path = directory
                pathString = directory.path
            }
        }
        .onChange(of: isTextFieldFocused) { _ ,focused in
            if !focused && isEditing {
                // Auto-commit when focus is lost
                commitEdit()
            }
        }
    }
    
    private var editingView: some View {
        HStack {
            TextField("Type path and press Enter...", text: $pathString)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .focused($isTextFieldFocused)
                .onSubmit {
                    commitEdit()
                }
                .onAppear {
                    // Ensure focus happens after view is rendered
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isTextFieldFocused = true
                        // Select all text for easy replacement
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            if let textField = NSApp.keyWindow?.firstResponder as? NSTextField {
                                textField.selectText(nil)
                            }
                        }
                    }
                }
                .onExitCommand {
                    cancelEdit()
                }
            
            // Cancel button
            Button(action: cancelEdit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(0.7)
        }
        .padding(.horizontal, 12)
    }
    
    private var breadcrumbView: some View {
        ZStack {
            // Background area for click detection - activates editing mode
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    startEditing()
                }
            
            HStack(spacing: 2) {
                // Navigation buttons
                HStack(spacing: 8) {
                    // Back button
                    Button(action: {
                        viewModel.navigateBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(viewModel.canNavigateBack() ? Color.accentColor : .gray.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!viewModel.canNavigateBack())
                    .help("Go back")
                    
                    // Forward button
                    Button(action: {
                        viewModel.navigateForward()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(viewModel.canNavigateForward() ? Color.accentColor : .gray.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!viewModel.canNavigateForward())
                    .help("Go forward")
                    
                    Divider()
                        .frame(height: 16)
                }
                .padding(.leading, 8)
                
                let components = pathComponents(path: URL(fileURLWithPath: pathString))
                let originalComponents = originalPathComponents(path: URL(fileURLWithPath: pathString))
                
                // Folder icon at the start
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.accentColor.opacity(0.8))
                    .padding(.leading, 4) // Reduced leading padding as we have navigation buttons now
                
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    HStack(spacing: 0) {
                        // Path separator
                        Text("/")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 3)
                        
                        // Clickable path component with fancy styling and context menu
                        Text(component)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(index == components.count - 1 ? .primary : Color.accentColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(index == components.count - 1 ?
                                          Color.accentColor.opacity(0.1) :
                                          Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(index == components.count - 1 ?
                                            Color.accentColor.opacity(0.3) :
                                            Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateToComponent(at: index, components: originalComponents)
                            }
                            .onHover { isHovering in
                                // Could add visual hover effects here
                            }
                            .contextMenu {
                                contextMenuForComponent(at: index, components: originalComponents, displayComponent: component)
                            }
                            .allowsHitTesting(true) // Ensure path components are clickable
                    }
                }
                
                Spacer()
                
                // Edit button
                Button(action: startEditing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 12)
                .opacity(0.6)
                .allowsHitTesting(true) // Ensure button is clickable
            }
            .allowsHitTesting(true) // Make sure the HStack and its contents can receive events
        }
    }
    
    // MARK: - Context Menu
    @ViewBuilder
    private func contextMenuForComponent(at index: Int, components: [String], displayComponent: String) -> some View {
        let targetPath = getPathForComponent(at: index, components: components)
        
        Button(action: {
            navigateToComponent(at: index, components: components)
        }) {
            Label("Go to \(displayComponent)", systemImage: "folder")
        }
        
        Button(action: {
            copyPathToClipboard(targetPath)
        }) {
            Label("Copy Path", systemImage: "doc.on.doc")
        }
        
        Button(action: {
            showInFinder(targetPath)
        }) {
            Label("Show in Finder", systemImage: "magnifyingglass")
        }
        
        Divider()
        
        Button(action: {
            openInTerminal(targetPath)
        }) {
            Label("Open in Terminal", systemImage: "terminal")
        }
    }
    
    // MARK: - Helper Methods for Context Menu Actions
    
    private func getPathForComponent(at index: Int, components: [String]) -> String {
        // Special case for home directory (~)
        let displayComponents = pathComponents(path: URL(fileURLWithPath: pathString))
        if index < displayComponents.count && displayComponents[index] == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        
        // For typical file paths, rebuild the path based on original components
        let fullPath = URL(fileURLWithPath: pathString)
        let levelsUp = displayComponents.count - index - 1
        
        var targetPath = fullPath
        for _ in 0..<levelsUp {
            targetPath = targetPath.deletingLastPathComponent()
        }
        
        return targetPath.path
    }
    
    private func copyPathToClipboard(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        
        // Optional: Show a brief confirmation (you could add a toast notification here)
        print("Copied path to clipboard: \(path)")
    }
    
    private func showInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    private func openInTerminal(_ path: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(path.replacingOccurrences(of: "'", with: "\\'"))'"
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
    
    private func pathComponents(path: URL) -> [String] {
        let components = path.pathComponents.filter { $0 != "/" }
        
        // Show home symbol for user directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.path.hasPrefix(homeDir) {
            var modifiedComponents = components
            if let userIndex = modifiedComponents.firstIndex(where: { component in
                homeDir.contains(component) && component != "Users"
            }) {
                modifiedComponents[userIndex] = "~"
                // Remove "Users" if it exists before the home directory
                if userIndex > 0 && modifiedComponents[userIndex - 1] == "Users" {
                    modifiedComponents.remove(at: userIndex - 1)
                }
            }
            return modifiedComponents
        }
        
        return components.isEmpty ? ["Root"] : components
    }
    
    private func originalPathComponents(path: URL) -> [String] {
        return path.pathComponents.filter { $0 != "/" }
    }
    
    private func navigateToComponent(at index: Int, components: [String]) {
        // Special case for root level
        if index == -1 || components.isEmpty {
            viewModel.navigateToPath("/")
            return
        }
        
        // Get the current display components (what user sees)
        let displayComponents = pathComponents(path: URL(fileURLWithPath: pathString))
        
        // Special case for home directory (~)
        if index < displayComponents.count && displayComponents[index] == "~" {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            viewModel.navigateToPath(homePath)
            return
        }
        
        // Get the clicked component name
        _ = displayComponents[index]
        
        // For typical file paths, rebuild the path based on original components
        let fullPath = URL(fileURLWithPath: pathString)
        
        // When user clicks breadcrumbs from right to left, we need to go up in the path
        // Calculate how many levels to go up: total components minus clicked index minus 1
        let levelsUp = displayComponents.count - index - 1
        
        // Apply the changes
        var targetPath = fullPath
        for _ in 0..<levelsUp {
            targetPath = targetPath.deletingLastPathComponent()
        }
        
        // Navigate to the constructed path
        viewModel.navigateToPath(targetPath.path)
    }
    
    private func startEditing() {
        withAnimation(.snappy(duration: 0.2)) {
            isEditing = true
        }
    }
    
    private func commitEdit() {
        let trimmedPath = pathString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Expand tilde to home directory
        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        
        // Validate path exists before navigating
        if FileManager.default.fileExists(atPath: expandedPath) {
            // Only navigate if the path has actually changed
            if expandedPath != path.path {
                viewModel.navigateToPath(expandedPath)
            }
        } else {
            // Revert to current path if invalid
            pathString = path.path
            // Could add error feedback here
        }
        
        isTextFieldFocused = false
    }
    
    private func cancelEdit() {
        pathString = path.path
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        isTextFieldFocused = false
    }
}
