import SwiftUI
import UniformTypeIdentifiers
import AppKit
import QuickLook

struct DirectoryView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    var onActivate: (() -> Void)? = nil

    @State private var selectedItems: Set<DirectoryItem.ID> = []
    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @ObservedObject private var thumbnailLoader = SimpleThumbnailLoader()
    
    // Column width percentages
    private let dateModifiedWidthPercent: CGFloat = 0.25
    private let kindWidthPercent: CGFloat = 0.20
    private let sizeWidthPercent: CGFloat = 0.15
    private let nameWidthPercent: CGFloat = 0.40
    
    init(viewModel: DirectoryViewModel = DirectoryViewModel(), onActivate: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onActivate = onActivate
    }
    
    @State private var sortColumn: SortColumn = .dateModified
    @State private var sortAscending: Bool = false
    
    enum SortColumn {
        case name, size, fileType, dateModified
    }

    // Computed property to get sorted items
    private var sortedItems: [DirectoryItem] {
        viewModel.items.sorted { item1, item2 in
            let comparison: ComparisonResult
            
            switch sortColumn {
            case .name:
                let name1 = item1.name ?? ""
                let name2 = item2.name ?? ""
                comparison = name1.localizedCaseInsensitiveCompare(name2)
            case .size:
                let size1 = item1.size ?? 0
                let size2 = item2.size ?? 0
                if size1 < size2 {
                    comparison = .orderedAscending
                } else if size1 > size2 {
                    comparison = .orderedDescending
                } else {
                    comparison = .orderedSame
                }
            case .fileType:
                let type1 = item1.fileType?.localizedDescription ?? ""
                let type2 = item2.fileType?.localizedDescription ?? ""
                comparison = type1.localizedCaseInsensitiveCompare(type2)
            case .dateModified:
                let date1 = item1.lastModified ?? Date.distantPast
                let date2 = item2.lastModified ?? Date.distantPast
                comparison = date1.compare(date2)
            }
            
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    var body: some View {
        VStack {
            PathBar(
                path: viewModel.currentDirectory ?? URL(fileURLWithPath: "/Users"),
                viewModel: viewModel,
                sortColumn: $sortColumn,
                sortAscending: $sortAscending
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onActivate?()
            }
            
            // Directory contents
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onActivate?()
                    }
            } else if let error = viewModel.errorMessage {
                VStack {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                    Button("Try Again") {
                        viewModel.loadDownloadsDirectory()
                        onActivate?()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    onActivate?()
                }
            } else {
                Table(sortedItems, selection: $selectedItems) {
                    TableColumn("Name") { item in
                        HStack {
                            ImageIcon(item: .constant(item))
                                .frame(width: 16, height: 16)
                             
                            Text(item.name ?? "Unknown")
                                .truncationMode(.middle)
                        }
                    }
                    .width(min: 180).alignment(.leading)

                    TableColumn("Size") { item in
                        if item.isDirectory {
                            Text("--")
                        } else if let size = item.size {
                            Text(viewModel.formatFileSize(size))
                        } else {
                            Text("--")
                        }
                    }
                    .width(min: 100).alignment(.trailing)
                    
                    TableColumn("Kind") { (item: DirectoryItem) in
                        if let fileType = item.fileType {
                            Text(fileType.localizedDescription ?? "Unknown")
                        } else {
                            Text("--")
                        }
                    }.alignment(.trailing)
                    
                    TableColumn("Date Modified") { item in
                        if let modifiedDate = item.lastModified {
                            Text(formatDate(modifiedDate))
                        } else {
                            Text("--")
                        }
                    }
                    .width(min: 150).alignment(.trailing)
                }
                .onChange(of: selectedItems) { _ in
                    onActivate?()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onActivate?()
                }
                .contextMenu(forSelectionType: DirectoryItem.ID.self) { ids in
                    Button("Open") {
                        for id in ids {
                            if let item = sortedItems.first(where: { $0.id == id }) {
                                viewModel.openItem(item)
                            }
                        }
                    }
                    
                    Button("Copy Path") {
                        for id in ids {
                            if let item = sortedItems.first(where: { $0.id == id }) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.url.path, forType: .string)
                            }
                        }
                    }
                    Button("Quick Look") {
                        if let firstId = ids.first,
                           let item = sortedItems.first(where: { $0.id == firstId }) {
                            openQuickLook(for: item.url)
                        }
                    }
                    Button("Open In Finder") {
                        for id in ids {
                            if let item = sortedItems.first(where: { $0.id == id }) {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                    }
                } primaryAction: { ids in
                    for id in ids {
                        if let item = sortedItems.first(where: { $0.id == id }) {
                            viewModel.openItem(item)
                        }
                    }
                    onActivate?()
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
        .frame(minHeight: 400)
        .focusable()
    }
    
    private func setSortColumn(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }
    
    private var selectedItemURLs: [URL] {
        selectedItems.compactMap { id in
            sortedItems.first(where: { $0.id == id })?.url
        }
    }
    
    private func handleSpaceKeyPress() {
        guard let firstSelectedId = selectedItems.first,
              let selectedItem = sortedItems.first(where: { $0.id == firstSelectedId }) else {
            return
        }
        
        openQuickLook(for: selectedItem.url)
    }
    
    private func openQuickLook(for url: URL) {
        quickLookURL = url
        showQuickLook = true
    }
    
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
