import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers



struct DirectoryView: View {
    @Bindable var viewModel: DirectoryViewModel
    var onActivate: (() -> Void)? = nil

    @State private var selectedItems: Set<DirectoryItem.ID> = []
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var itemToRename: DirectoryItem?

    @State private var sortOrder: [KeyPathComparator<DirectoryItem>] =
        SettingsModel.keyPathComparator(
            for: SettingsModel.shared.defaultSortMethod
        )

    init(
        viewModel: DirectoryViewModel = DirectoryViewModel(),
        onActivate: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onActivate = onActivate
    }

    var body: some View {
        return VStack(spacing: 0) {
            if let currentDirectory = viewModel.currentDirectory {
                PathBar(
                    path: currentDirectory,
                    viewModel: viewModel
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onActivate?()
                }
            } else {
                // Show empty path bar while loading
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 10)
            }
            
            // Error banner
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button(action: {
                        viewModel.errorMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack {
                Group {
                    if viewModel.viewMode == .grid {
                            DirectoryGridView(
                                viewModel: viewModel,
                                selectedItems: $selectedItems,
                                sortOrder: $sortOrder,
                                quickLookAction: openQuickLook
                            )
                        } else {
                            DirectoryTableView(
                                viewModel: viewModel,
                                selectedItems: $selectedItems,
                                sortOrder: $sortOrder
                            )
                        }
                    }
                    .modifier(
                        DirectoryContextMenu(
                            viewModel: viewModel,
                            ids: selectedItems,
                            quickLookAction: openQuickLook
                        )
                    )
                    .onChange(of: sortOrder) { _, newSortOrder in
                        viewModel.setSortOrder(newSortOrder)
                    }
                    .onAppear {
                        sortOrder = SettingsModel.keyPathComparator(
                            for: SettingsModel.shared.defaultSortMethod
                        )
                        viewModel.setSortOrder(sortOrder)
                    }
                    .onChange(of: SettingsModel.shared.defaultSortMethod) {
                        _,
                        newMethod in
                        sortOrder = SettingsModel.keyPathComparator(
                            for: newMethod
                        )
                        viewModel.setSortOrder(sortOrder)
                    }
                    .onChange(of: viewModel.currentDirectory) { _, _ in
                        // Sorting is handled by the view model
                    }
                    .onChange(of: selectedItems) {
                        onActivate?()
                    }
                    .onDrag(dragProvider)
                    .onDrop(
                        of: [UTType.fileURL],
                        delegate: DirectoryDropDelegate(viewModel: viewModel)
                    )
                    .onKeyPress(.space) {
                        handleSpaceKeyPress()
                        return .handled
                    }

                if viewModel.isLoading {
                    LoadingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                        .zIndex(1)
                }
            }
        }
        .frame(minHeight: 400)
        .focusable()
        .popoverTip(QuickLookTip(), arrowEdge: .bottom)
        .alert("Rename", isPresented: $viewModel.showingRenameAlert) {
            TextField("Name", text: $viewModel.renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                viewModel.performRename()
            }
        } message: {
            Text("Enter a new name for the item")
        }
        .alert("Replace Files?", isPresented: $viewModel.showingFileConflictAlert) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelReplaceFiles()
            }
            Button("Replace") {
                viewModel.confirmReplaceFiles()
            }
        } message: {
            Text(viewModel.conflictMessage)
        }
    }

    // MARK: - Drag and Drop

    private func dragProvider() -> NSItemProvider {
        let selectedURLs = selectedItems.compactMap { id in
            viewModel.sortedItems.first { $0.id == id }?.url
        }

        guard !selectedURLs.isEmpty else { return NSItemProvider() }

        let provider = NSItemProvider()

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            do {
                let data = try NSKeyedArchiver.archivedData(
                    withRootObject: selectedURLs,
                    requiringSecureCoding: false
                )
                completion(data, nil)
                return nil  // Return nil for the progress object
            } catch {
                completion(nil, error)
                return nil  // Return nil for the progress object
            }
        }
        return provider
    }

    // MARK: - Sorting Helper
    // Sorting is now handled by DirectoryViewModel

    private var selectedItemURLs: [URL] {
        selectedItems.compactMap { id in
            viewModel.sortedItems.first { $0.id == id }?.url
        }
    }

    // MARK: - Key Press Actions

    private func handleSpaceKeyPress() {
        guard !selectedItems.isEmpty else { return }
        
        let selectedURLs = selectedItemURLs
        guard !selectedURLs.isEmpty else { return }
        
        // Use the shared Quick Look service
        QuickLookService.shared.showPreview(for: selectedURLs, startingAt: 0)
    }

    private func openQuickLook(for url: URL) {
        // Use the shared Quick Look service for single file preview
        QuickLookService.shared.showPreview(for: [url], startingAt: 0)
    }
}
