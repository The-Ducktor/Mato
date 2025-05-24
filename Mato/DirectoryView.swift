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
    @ObservedObject private var thumbnailLoader = SimpleThumbnailLoader()

    // Column width percentages
    private let dateModifiedWidthPercent: CGFloat = 0.25
    private let kindWidthPercent: CGFloat = 0.20
    private let sizeWidthPercent: CGFloat = 0.15
    private let nameWidthPercent: CGFloat = 0.40

    init(
        viewModel: DirectoryViewModel = DirectoryViewModel(),
        onActivate: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onActivate = onActivate
    }
    @State private var sortOrder = [
        KeyPathComparator(\DirectoryItem.lastModified, order: .reverse),
        
    ]

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
                Table(viewModel.items, selection: $selectedItems, sortOrder: $sortOrder) {
                    
                    TableColumn("Name", value: \.name) { item in
                        HStack {
                            ImageIcon(item: .constant(item))
                                .frame(width: 16, height: 16)
                            Text(item.name)
                                .truncationMode(.middle)
                        }
                    }
                    .width(min: 180)
                    .alignment(.leading)

                    TableColumn("Size", value: \.size) { item in
                        if item.isDirectory {
                            Text("--")
                        } else {
                            Text(viewModel.formatFileSize(item.size))
                        }
                    }
                    .width(min: 100)
                    .alignment(.trailing)

                    TableColumn("Kind", value: \.fileTypeDescription) { item in
                        Text(item.fileTypeDescription)
                    }
                    .alignment(.trailing)

                    TableColumn("Date Modified", value: \.lastModified) { item in
                        Text(formatDate(item.lastModified))
                    }
                    .width(min: 150)
                    .alignment(.trailing)
                


                }.onChange(of: sortOrder) { _, sortOrder in
                    viewModel.items.sort(using: sortOrder)
                }.onAppear() {
                    viewModel.items.sort(using: sortOrder)
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
                            if let item = viewModel.items.first(where: {
                                $0.id == id
                            }) {
                                viewModel.openItem(item)
                            }
                        }
                    }

                    Button("Copy Path") {
                        for id in ids {
                            if let item = viewModel.items.first(where: {
                                $0.id == id
                            }) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    item.url.path,
                                    forType: .string
                                )
                            }
                        }
                    }
                    Button("Quick Look") {
                        if let firstId = ids.first,
                            let item = viewModel.items.first(where: {
                                $0.id == firstId
                            })
                        {
                            openQuickLook(for: item.url)
                        }
                    }
                    Button("Open In Finder") {
                        for id in ids {
                            if let item = viewModel.items.first(where: {
                                $0.id == id
                            }) {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    item.url
                                ])
                            }
                        }
                    }
                } primaryAction: { ids in
                    for id in ids {
                        if let item = viewModel.items.first(where: {
                            $0.id == id
                        }) {
                            viewModel.openItem(item)
                        }
                    }
                    onActivate?()
                }.onChange(of: sortOrder) { _, sortOrder in
                    viewModel.items.sort(using: sortOrder)
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

    private var selectedItemURLs: [URL] {
        selectedItems.compactMap { id in
            viewModel.items.first(where: { $0.id == id })?.url
        }
    }

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

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date)
            || calendar.isDateInTomorrow(date)
        {
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
