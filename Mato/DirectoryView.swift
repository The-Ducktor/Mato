import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct DirectoryView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    var onActivate: (() -> Void)? = nil

    @State private var selectedItems: Set<DirectoryItem.ID> = []
    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var itemToRename: DirectoryItem?

    @State private var sortOrder = [
        KeyPathComparator(\DirectoryItem.lastModified, order: .reverse)
    ]

    init(
        viewModel: DirectoryViewModel = DirectoryViewModel(),
        onActivate: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onActivate = onActivate
    }

    var body: some View {
        VStack {
            PathBar(
                path: viewModel.currentDirectory
                    ?? URL(fileURLWithPath: "/Users"),
                viewModel: viewModel
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onActivate?()
            }

            if viewModel.isLoading {
                LoadingView()
            } else if let error = viewModel.errorMessage {
                ErrorView(error: error) {
                    viewModel.loadDownloadsDirectory()
                    onActivate?()
                }
            } else {
                DirectoryTableView(
                    viewModel: viewModel,
                    selectedItems: $selectedItems,
                    sortOrder: $sortOrder
                )
                .modifier(DirectoryContextMenu(viewModel: viewModel, ids: selectedItems, quickLookAction: openQuickLook))
                .onChange(of: sortOrder) { _, newSortOrder in
                    applySorting(with: newSortOrder)
                }
                .onAppear {
                    applySorting(with: sortOrder)
                }
                .onChange(of: viewModel.currentDirectory) { _, _ in
                    applySorting(with: sortOrder)
                }
                .onChange(of: viewModel.items) { _, _ in
                    applySorting(with: sortOrder)
                }
                .onChange(of: selectedItems) {
                    onActivate?()
                }
                .onDrag(dragProvider)
                .onDrop(of: [UTType.fileURL], delegate: DirectoryDropDelegate(viewModel: viewModel))
                .onKeyPress(.space) {
                    handleSpaceKeyPress()
                    return .handled
                }
                .quickLookPreview($quickLookURL, in: selectedItemURLs)
            }
        }
        .frame(minHeight: 400)
        .focusable()
        .alert("Rename", isPresented: $viewModel.showingRenameAlert) {
            TextField("Name", text: $viewModel.renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                viewModel.performRename()
            }
        } message: {
            Text("Enter a new name for the item")
        }
    }

    // MARK: - Drag and Drop

    private func dragProvider() -> NSItemProvider {
        let selectedItems = viewModel.items.filter { self.selectedItems.contains($0.id) }
        let providers = selectedItems.map { item -> NSItemProvider in
            let provider = NSItemProvider(item: item.url as NSURL, typeIdentifier: UTType.fileURL.identifier)
            provider.suggestedName = item.name
            return provider
        }
        return providers.first ?? NSItemProvider()
    }

    // MARK: - Sorting Helper

    private func applySorting(with sortOrder: [KeyPathComparator<DirectoryItem>]) {
        DispatchQueue.main.async {
            viewModel.items.sort(using: sortOrder)
        }
    }

    private var selectedItemURLs: [URL] {
        selectedItems.compactMap { id in
            viewModel.items.first { $0.id == id }?.url
        }
    }

    // MARK: - Key Press Actions

    private func handleSpaceKeyPress() {
        guard let firstSelectedId = selectedItems.first,
            let selectedItem = viewModel.items.first(where: {
                $0.id == firstSelectedId
            })
        else {
            return
        }

        openQuickLook(for: selectedItem.url)
    }

    private func openQuickLook(for url: URL) {
        quickLookURL = url
        showQuickLook = true
    }
}

extension DirectoryViewModel {
    func refreshCurrentDirectory() {
        if let currentDir = currentDirectory {
            loadDirectory(at: currentDir)
        }
    }
}
