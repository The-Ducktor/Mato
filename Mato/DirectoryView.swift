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
        KeyPathComparator(\DirectoryItem.creationDate, order: .reverse)
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

            ZStack {
                if let error = viewModel.errorMessage {
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
        let selectedURLs = selectedItems.compactMap { id in
            viewModel.items.first { $0.id == id }?.url
        }

        guard !selectedURLs.isEmpty else { return NSItemProvider() }

        let provider = NSItemProvider()

        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: selectedURLs, requiringSecureCoding: false)
                completion(data, nil)
                return nil // Return nil for the progress object
            } catch {
                completion(nil, error)
                return nil // Return nil for the progress object
            }
        }
        return provider
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
