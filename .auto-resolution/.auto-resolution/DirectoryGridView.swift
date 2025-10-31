import SwiftUI
import UniformTypeIdentifiers

struct DirectoryGridView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    @Binding var sortOrder: [KeyPathComparator<DirectoryItem>]
    var quickLookAction: ((URL) -> Void)?

    @StateObject private var audioPlayer = AudioPlayerService.shared
    @State private var hoveredItemID: DirectoryItem.ID?
    @State private var isDropTargeted: Bool = false

    // Grid configuration
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.sortedItems) { item in
                    GridItemView(
                        item: item,
                        isSelected: selectedItems.contains(item.id),
                        isHovered: hoveredItemID == item.id,
                        viewModel: viewModel,
                        selectedItems: $selectedItems,
                        quickLookAction: quickLookAction
                    )
                    .onTapGesture {
                        handleTap(item: item)
                    }
                    .onTapGesture(count: 2) {
                        handleDoubleTap(item: item)
                    }
                    .onHover { hovering in
                        hoveredItemID = hovering ? item.id : nil
                    }
                    .draggable(makeDraggedFiles(for: item))
                }
            }
            .padding()
        }
        .onDrop(
            of: [UTType.fileURL],
            delegate: GridDropDelegate(viewModel: viewModel)
        )
        .onChange(of: viewModel.currentDirectory) { _, _ in
            // Clear selection when changing directories
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedItems.removeAll()
            }
        }
        .onKeyPress(.space) {
            handleSpaceKeyPress()
            return .handled
        }
        .focusable()
    }
    
    private func handleSpaceKeyPress() {
        guard let firstSelectedId = selectedItems.first,
              let selectedItem = viewModel.sortedItems.first(where: { $0.id == firstSelectedId })
        else {
            return
        }
        
        quickLookAction?(selectedItem.url)
    }

    private func handleTap(item: DirectoryItem) {
        if NSEvent.modifierFlags.contains(.command) {
            // Toggle selection
            if selectedItems.contains(item.id) {
                selectedItems.remove(item.id)
            } else {
                selectedItems.insert(item.id)
            }
        } else if NSEvent.modifierFlags.contains(.shift) {
            // Range selection (simplified for grid)
            selectedItems.insert(item.id)
        } else {
            // Single selection
            selectedItems = [item.id]
        }
    }

    private func handleDoubleTap(item: DirectoryItem) {
        viewModel.openItem(item)
    }

    private func makeDraggedFiles(for item: DirectoryItem) -> DraggedFiles {
        let urlsToDrag: [URL]
        if selectedItems.contains(item.id), selectedItems.count > 1 {
            let selectedSet = selectedItems
            urlsToDrag = viewModel.sortedItems.reduce(into: []) {
                result,
                current in
                if selectedSet.contains(current.id) {
                    result.append(current.url)
                }
            }
        } else {
            urlsToDrag = [item.url]
        }
        return DraggedFiles(urls: urlsToDrag)
    }
}

// MARK: - Grid Item View
struct GridItemView: View {
    let item: DirectoryItem
    let isSelected: Bool
    let isHovered: Bool
    let viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    var quickLookAction: ((URL) -> Void)?

    @StateObject private var audioPlayer = AudioPlayerService.shared
    @State private var isDropTargeted = false

    private var isPlayable: Bool {
        audioPlayer.isPlayableMedia(item)
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentlyPlayingURL == item.url && audioPlayer.isPlaying
    }

    var body: some View {
        VStack(spacing: 4) {
            // Icon with play/pause button overlay
            ZStack(alignment: .center) {
                ImageIcon(item: .constant(item), isPlayable: true)
                    .frame(width: 64, height: 64)

                // Show play/pause button for playable media
                if isPlayable && (isHovered || isCurrentlyPlaying) {
                    Button(action: {
                        audioPlayer.togglePlayback(for: item.url)
                    }) {
                        ZStack {
                            // Background circle
                            Circle()
                                .frame(width: 28, height: 28).glassEffect()

                            // Play or pause icon
                            Image(
                                systemName: isCurrentlyPlaying
                                    ? "pause.fill" : "play.fill"
                            )
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .offset(x: isCurrentlyPlaying ? 0 : 1)  // Slight offset for play icon to center it visually
                        }
                        .shadow(
                            color: .black.opacity(0.3),
                            radius: 2,
                            x: 0,
                            y: 1
                        )
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(true)
                }
            }

            // Name
            Text(
                item.isAppBundle
                    ? item.url.deletingPathExtension().lastPathComponent
                    : item.name
            )
            .font(.caption)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .truncationMode(.middle)
            .frame(height: 20)
        }
        .frame(width: 100, height: 100)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .contextMenu {
            Button("Open") {
                viewModel.openItem(item)
            }

            Button("Open in Terminal") {
                viewModel.openInTerminal([item.id])
            }
            .disabled(!item.isDirectory)

            Divider()

            Button("Copy") {
                viewModel.copyItems([item.id])
            }

            Button("Cut") {
                viewModel.cutItems([item.id])
            }

            if viewModel.hasItemsInPasteboard() {
                Button("Paste") {
                    viewModel.pasteItems()
                }
            }

            Divider()

            Button("Copy Path") {
                viewModel.copyPaths([item.id])
            }

            Button("Copy as Pathname") {
                viewModel.copyAsPathname([item.id])
            }

            Divider()

            Button("Quick Look") {
                quickLookAction?(item.url)
            }

            Button("Show in Finder") {
                viewModel.showInFinder([item.id])
            }

            if item.url.pathExtension.lowercased().contains("app") || item.isDirectory {
                Button("Show Package Contents") {
                    viewModel.showPackageContents(item)
                }
            }

            Divider()

            if viewModel.canCompress([item.id]) {
                Button("Compress \"\(item.name)\"") {
                    viewModel.compressItems([item.id])
                }
            }

            if viewModel.canCreateAlias([item.id]) {
                Button("Make Alias") {
                    viewModel.makeAlias([item.id])
                }
            }

            Button("Move to Trash") {
                viewModel.moveToTrash([item.id])
            }
            .foregroundColor(.red)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) {
            providers in
            guard item.isDirectory else { return false }

            Task {
                var files: [URL] = []

                for provider in providers {
                    if let urls = try? await loadFileURLs(from: provider) {
                        for url in urls {
                            if item.url == url {
                                continue
                            }
                            if item.isDirectory {
                                files.append(url)
                            }
                        }
                    }
                }

                if !files.isEmpty {
                    viewModel.moveFiles(from: files, to: item.url)
                }
            }
            return true
        }
    }

    private var backgroundFill: Color {
        if isDropTargeted && item.isDirectory {
            return Color.accentColor.opacity(0.25)
        } else if isSelected {
            return Color.primary.opacity(0.15)
        } else if isHovered {
            return Color.accentColor.opacity(0.05)
        } else {
            return Color.clear
        }
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor : Color.clear
    }

    private func loadFileURLs(from provider: NSItemProvider) async throws
        -> [URL]
    {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = data as? URL {
                    continuation.resume(returning: [url])
                    return
                }

                if let data = data as? Data {
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClasses: [NSArray.self, NSURL.self],
                        from: data
                    ) as? [URL] {
                        continuation.resume(returning: urls)
                        return
                    }

                    if let url = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClass: NSURL.self,
                        from: data
                    ) as? URL {
                        continuation.resume(returning: [url])
                        return
                    }

                    if let url = URL(dataRepresentation: data, relativeTo: nil)
                    {
                        continuation.resume(returning: [url])
                        return
                    }
                }

                continuation.resume(
                    throwing: NSError(
                        domain: "InvalidData",
                        code: 0,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Could not decode URL from drag data"
                        ]
                    )
                )
            }
        }
    }
}

// MARK: - Grid Drop Delegate
struct GridDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel

    func performDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []

            for itemProvider in itemProviders {
                if let urlsFromProvider = try? await loadFileURLs(
                    from: itemProvider
                ) {
                    urls.append(contentsOf: urlsFromProvider)
                }
            }

            let uniqueURLs = Array(Set(urls))

            if !uniqueURLs.isEmpty,
                let currentDirectory = viewModel.currentDirectory
            {
                viewModel.moveFiles(from: uniqueURLs, to: currentDirectory)
            }
        }
        return true
    }

    private func loadFileURLs(from provider: NSItemProvider) async throws
        -> [URL]
    {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = data as? URL {
                    continuation.resume(returning: [url])
                    return
                }

                if let data = data as? Data {
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClasses: [NSArray.self, NSURL.self],
                        from: data
                    ) as? [URL] {
                        continuation.resume(returning: urls)
                        return
                    }

                    if let url = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClass: NSURL.self,
                        from: data
                    ) as? URL {
                        continuation.resume(returning: [url])
                        return
                    }

                    if let url = URL(dataRepresentation: data, relativeTo: nil)
                    {
                        continuation.resume(returning: [url])
                        return
                    }
                }

                continuation.resume(
                    throwing: NSError(
                        domain: "InvalidData",
                        code: 0,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Could not decode URL from drag data"
                        ]
                    )
                )
            }
        }
    }

    func dropEntered(info: DropInfo) {}
    func dropExited(info: DropInfo) {}
}
