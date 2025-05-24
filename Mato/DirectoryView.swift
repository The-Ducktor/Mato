import SwiftUI
import UniformTypeIdentifiers
import AppKit
import QuickLook

struct DirectoryView: View {
    @ObservedObject var viewModel: DirectoryViewModel

    @State private var selectedItems: Set<DirectoryItem.ID> = []
    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @ObservedObject private var thumbnailLoader = SimpleThumbnailLoader()
    
    init(viewModel: DirectoryViewModel = DirectoryViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack {
            PathBar(
                path: viewModel.currentDirectory ?? URL(
                    fileURLWithPath: "/Users"
                ),
                viewModel: viewModel
            )
            
            // Directory contents
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                    Button("Try Again") {
                        viewModel.loadDownloadsDirectory()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.items, selection: $selectedItems) {
                    
                    
                    TableColumn("Name") { item in
                        HStack {
                            
                            ImageIcon(item: .constant(item))
                                .frame(width: 16, height: 16) // Slightly larger size for visibility
                             
                            Text(item.name ?? "Unknown")
                                .truncationMode(.middle)
                        }
                    }
                    .width(min: 180)

                    
                    TableColumn("Size") { item in
                        if item.isDirectory {
                            Text("--")
                        } else if let size = item.size {
                            Text(viewModel.formatFileSize(size))
                        } else {
                            Text("--")
                        }
                    }
                    .width(min: 100)
                    
                    TableColumn("File Type") { (item: DirectoryItem) in
                        if let fileType = item.fileType {
                            Text(fileType.localizedDescription ?? "Unknown")
                        } else {
                            Text("--")
                        }
                    }
                    
                    TableColumn("Date Modified") { item in
                        if let modifiedDate = item.lastModified {
                            Text(formatDate(modifiedDate))
                        } else {
                            Text("--")
                        }
                    }
                    .width(min: 150)
                }
                .contextMenu(forSelectionType: DirectoryItem.ID.self) { ids in
                    Button("Open") {
                        for id in ids {
                            if let item = viewModel.items.first(where: { $0.id == id }) {
                                viewModel.openItem(item)
                            }
                        }
                    }
                    
                    Button("Copy Path") {
                        for id in ids {
                            if let item = viewModel.items.first(where: { $0.id == id }) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.url.path, forType: .string)
                            }
                        }
                    }
                    Button("Quick Look") {
                        if let firstId = ids.first,
                           let item = viewModel.items.first(where: { $0.id == firstId }) {
                            openQuickLook(for: item.url)
                        }
                    }
                    Button("Open In Finder") {
                        for id in ids {
                            if let item = viewModel.items.first(where: { $0.id == id }) {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }}
                    
                    
                } primaryAction: { ids in
                    for id in ids {
                        if let item = viewModel.items.first(where: { $0.id == id }) {
                            viewModel.openItem(item)
                        }
                    }
                }
                .onKeyPress(.space) {
                    handleSpaceKeyPress()
                    return .handled
                }
                .quickLookPreview(
                    $quickLookURL,
                    in: selectedItemURLs
                )
            }
        }
        .frame( minHeight: 400)
        .focusable()
    }
    
    private var selectedItemURLs: [URL] {
        selectedItems.compactMap { id in
            viewModel.items.first(where: { $0.id == id })?.url
        }
    }
    
    private func handleSpaceKeyPress() {
        // Get the first selected item
        guard let firstSelectedId = selectedItems.first,
              let selectedItem = viewModel.items.first(where: { $0.id == firstSelectedId }) else {
            return
        }
        
        openQuickLook(for: selectedItem.url)
    }
    
    private func openQuickLook(for url: URL) {
        quickLookURL = url
        showQuickLook = true
    }
    
    // Helper function to format dates
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) || calendar.isDateInTomorrow(date) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

}



