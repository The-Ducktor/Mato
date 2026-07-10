import SwiftUI
import UniformTypeIdentifiers

struct ItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [DirectoryItem.ID: CGRect] = [:]
    static func reduce(value: inout [DirectoryItem.ID: CGRect], nextValue: () -> [DirectoryItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct DirectoryGridView: View {
    var viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    @Binding var sortOrder: [KeyPathComparator<DirectoryItem>]
    var quickLookAction: ((URL) -> Void)?

    @State private var hoveredItemID: DirectoryItem.ID?
    @State private var isDropTargeted: Bool = false
    @FocusState private var isFocused: Bool
    @State private var containerWidth: CGFloat = 800
    @State private var cachedItemsPerRow: Int = 6
    @State private var hoverDebounceTask: Task<Void, Never>?

    // Marquee selection state
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var itemFrames: [DirectoryItem.ID: CGRect] = [:]
    @State private var initialSelectionAtMarqueeStart: Set<DirectoryItem.ID> = []

    // Grid configuration
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)
    ]

    /// Recompute cached column count when container width changes.
    private func updateItemsPerRow() {
        let itemMinWidth: CGFloat = 100
        let itemMaxWidth: CGFloat = 120
        let spacing: CGFloat = 16
        let padding: CGFloat = 32
        let availableWidth = containerWidth - padding
        let maxColumns = Int(availableWidth / (itemMinWidth + spacing))
        let actualItemWidth = (availableWidth - CGFloat(maxColumns - 1) * spacing) / CGFloat(maxColumns)
        if actualItemWidth > itemMaxWidth {
            cachedItemsPerRow = max(1, Int(availableWidth / (itemMaxWidth + spacing)))
        } else {
            cachedItemsPerRow = max(1, maxColumns)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.sortedItems, id: \.id) { item in
                        GridItemView(
                            item: item,
                            isSelected: selectedItems.contains(item.id),
                            isHovered: hoveredItemID == item.id,
                            viewModel: viewModel,
                            selectedItems: $selectedItems,
                            quickLookAction: quickLookAction
                        )
                        .id(item.id)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ItemFramePreferenceKey.self,
                                    value: [item.id: geo.frame(in: .named("grid"))]
                                )
                            }
                        )
                        .onTapGesture {
                            handleTap(item: item)
                        }
                        .onTapGesture(count: 2) {
                            handleDoubleTap(item: item)
                        }
                        .onHover { hovering in
                            handleHover(item: item, hovering: hovering)
                        }
                        .draggable(makeDraggedFiles(for: item))
                    }
                }
                .transaction { t in t.animation = nil } // Disable implicit animations
                .padding()
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Clear selection when clicking background
                            withTransaction(Transaction(animation: nil)) {
                                selectedItems.removeAll()
                            }
                        }
                )
            }
            .coordinateSpace(name: "grid")
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                itemFrames = frames
            }
            .overlay(
                // Marquee Rectangle
                Group {
                    if let start = marqueeStart, let current = marqueeCurrent {
                        let rect = marqueeRect(from: start, to: current)
                        Rectangle()
                            .stroke(Color.accentColor, lineWidth: 1)
                            .background(Color.accentColor.opacity(0.1))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            )
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if marqueeStart == nil {
                            marqueeStart = value.startLocation
                            initialSelectionAtMarqueeStart = selectedItems
                        }
                        marqueeCurrent = value.location
                        updateSelectionForMarquee()
                    }
                    .onEnded { _ in
                        marqueeStart = nil
                        marqueeCurrent = nil
                        initialSelectionAtMarqueeStart = []
                    }
            )
            .onAppear {
                containerWidth = geometry.size.width
                updateItemsPerRow()
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                // Use a transaction to ensure smooth updates
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    containerWidth = newWidth
                    updateItemsPerRow()
                }
            }
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
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.space) {
            handleSpaceKeyPress()
            return .handled
        }
        .onKeyPress(.return) {
            handleReturnKeyPress()
            return .handled
        }
        .onKeyPress(.upArrow) {
            handleArrowKey(.up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            handleArrowKey(.down)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            handleArrowKey(.left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            handleArrowKey(.right)
            return .handled
        }
    }
    
    private func handleSpaceKeyPress() {
        guard let firstSelectedId = selectedItems.first,
              let selectedItem = viewModel.sortedItems.first(where: { $0.id == firstSelectedId })
        else {
            return
        }
        
        quickLookAction?(selectedItem.url)
    }
    
    private func handleReturnKeyPress() {
        guard let firstSelectedId = selectedItems.first,
              let selectedItem = viewModel.sortedItems.first(where: { $0.id == firstSelectedId })
        else {
            return
        }
        
        viewModel.openItem(selectedItem)
    }
    
    private enum ArrowDirection {
        case up, down, left, right
    }
    
    private func handleArrowKey(_ direction: ArrowDirection) {
        let items = viewModel.sortedItems
        guard !items.isEmpty else { return }
        
        // If no selection, select the first item
        guard let currentId = selectedItems.first,
              let currentIndex = items.firstIndex(where: { $0.id == currentId }) else {
            selectedItems = [items[0].id]
            return
        }
        
        var newIndex = currentIndex
        
        switch direction {
        case .left:
            newIndex = max(0, currentIndex - 1)
        case .right:
            newIndex = min(items.count - 1, currentIndex + 1)
        case .up:
            newIndex = max(0, currentIndex - cachedItemsPerRow)
        case .down:
            newIndex = min(items.count - 1, currentIndex + cachedItemsPerRow)
        }
        
        // Only update if the index changed
        if newIndex != currentIndex {
            // Use transaction to improve performance
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if NSEvent.modifierFlags.contains(.shift) {
                    // Add to selection
                    selectedItems.insert(items[newIndex].id)
                } else {
                    // Replace selection
                    selectedItems = [items[newIndex].id]
                }
            }
        }
    }

    private func handleTap(item: DirectoryItem) {
       
        // Immediate update, no animation delay
        withTransaction(Transaction(animation: nil)) {
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
    }

    private func handleDoubleTap(item: DirectoryItem) {
        viewModel.openItem(item)
    }
    
    private func handleHover(item: DirectoryItem, hovering: Bool) {
        // Cancel any pending hover task
        hoverDebounceTask?.cancel()

        // Immediate update without animation
        withTransaction(Transaction(animation: nil)) {
            if hovering {
                // Set immediately for hover-in
                hoveredItemID = item.id
            } else {
                // Set immediately for hover-out
                hoveredItemID = nil
            }
        }

        // Preload directory contents after a short dwell time so fast mouse
        // movement doesn't trigger unnecessary fetches.
        guard hovering, item.isDirectory, !item.isAppBundle else { return }
        hoverDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            viewModel.preloadDirectory(at: item.url)
        }
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
    
    // MARK: - Marquee Helpers
    
    private func marqueeRect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(from.x - to.x),
            height: abs(from.y - to.y)
        )
    }
    
    private func updateSelectionForMarquee() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }
        let rect = marqueeRect(from: start, to: current)
        
        let commandPressed = NSEvent.modifierFlags.contains(.command)
        let shiftPressed = NSEvent.modifierFlags.contains(.shift)
        
        var newSelection = initialSelectionAtMarqueeStart
        
        for (id, frame) in itemFrames {
            if rect.intersects(frame) {
                newSelection.insert(id)
            } else if !commandPressed && !shiftPressed {
                // If not multi-selecting, remove items not in rect
                if !initialSelectionAtMarqueeStart.contains(id) {
                    newSelection.remove(id)
                }
            }
        }
        
        // Final pass for non-multi-select: only items in rect or previously selected (if multi)
        if !commandPressed && !shiftPressed {
            for id in newSelection {
                if let frame = itemFrames[id], !rect.intersects(frame) {
                    newSelection.remove(id)
                }
            }
        }

        withTransaction(Transaction(animation: nil)) {
            selectedItems = newSelection
        }
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

    var audioPlayer = AudioPlayerService.shared
    @State private var isDropTargeted = false
    @State private var showProgressRing = false
    @State private var isPressed = false
    @State private var optimisticPlayState: Bool?
    @State private var cachedIsPlayable: Bool = false

    private var isPlayable: Bool {
        cachedIsPlayable
    }

    private var isCurrentlyPlaying: Bool {
        // Use optimistic state if available, otherwise use actual state
        if let optimistic = optimisticPlayState {
            return audioPlayer.currentlyPlayingURL == item.url && optimistic
        }
        return audioPlayer.currentlyPlayingURL == item.url && audioPlayer.isPlaying
    }
    
    private var isCurrentFile: Bool {
        audioPlayer.currentlyPlayingURL == item.url
    }
    
    private var progressValue: CGFloat {
        guard isCurrentFile,
              audioPlayer.duration > 0 else {
            return 0
        }
        return CGFloat(audioPlayer.currentTime / audioPlayer.duration)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Icon with play/pause button overlay
            ZStack(alignment: .center) {
                ImageIcon(item: .constant(item), isPlayable: true)
                    .frame(width: 64, height: 64)

                // Show play/pause button for playable media
                if isPlayable && (isHovered || isCurrentFile) {
                    Button(action: {
                        // Optimistic update - immediately flip the state
                        if isCurrentFile {
                            optimisticPlayState = !audioPlayer.isPlaying
                        } else {
                            optimisticPlayState = true
                        }
                        
                        // Clear optimistic state after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            optimisticPlayState = nil
                        }
                        
                        audioPlayer.togglePlayback(for: item.url)
                    }) {
                        ZStack {
                            // Progress ring (show for current file, whether playing or paused)
                            if isCurrentFile && showProgressRing {
                                // Background ring
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.3),
                                        lineWidth: 2.5
                                    )
                                    .frame(width: 32, height: 32)
                                    .scaleEffect(showProgressRing ? 1.0 : 0.0)
                                    .opacity(showProgressRing ? 1.0 : 0.0)
                                
                                // Progress ring
                                Circle()
                                    .trim(from: 0, to: progressValue)
                                    .stroke(
                                        Color.white,
                                        style: StrokeStyle(
                                            lineWidth: 2.5,
                                            lineCap: .round
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                    .rotationEffect(.degrees(-90))
                                    .scaleEffect(showProgressRing ? 1.0 : 0.0)
                                    .opacity(showProgressRing ? 1.0 : 0.0)
                            }
                            
                            // Background circle
                            Circle()
                                .frame(width: 28, height: 28).glassEffect()
                                .scaleEffect(isPressed ? 0.9 : 1.0)

                            // Play or pause icon
                            Image(
                                systemName: isCurrentlyPlaying
                                    ? "pause.fill" : "play.fill"
                            )
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .offset(x: isCurrentlyPlaying ? 0 : 1)
                            .scaleEffect(isPressed ? 0.85 : 1.0)
                            .contentTransition(.symbolEffect(.replace))
                        }
                        .shadow(
                            color: .black.opacity(0.3),
                            radius: 2,
                            x: 0,
                            y: 1
                        )
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showProgressRing)
                        .animation(.linear(duration: 0.05), value: progressValue)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(true)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isPressed {
                                    isPressed = true
                                }
                            }
                            .onEnded { _ in
                                isPressed = false
                            }
                    )
                }
            }
            .onChange(of: isCurrentFile) { _, isCurrent in
                withAnimation {
                    showProgressRing = isCurrent
                }
            }
            .onAppear {
                showProgressRing = isCurrentFile
                cachedIsPlayable = audioPlayer.isPlayableMedia(item)
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
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .contextMenu {
            DirectoryContextMenuItems(
                viewModel: viewModel,
                ids: [item.id],
                quickLookAction: quickLookAction
            )
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) {
            providers in
            guard item.isDirectory else { return false }

            Task {
                var files: [URL] = []

                for provider in providers {
                    if let urls = try? await provider.loadFileURLs() {
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
            return Color.accentColor.opacity(0.15)
        } else if isSelected {
            return Color.accentColor.opacity(0.12)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        } else {
            return Color.clear
        }
    }

    private var borderColor: Color {
        if isDropTargeted && item.isDirectory {
            return Color.accentColor.opacity(0.5)
        } else if isSelected {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color.clear
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
                if let urlsFromProvider = try? await itemProvider.loadFileURLs() {
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

    func dropEntered(info: DropInfo) {}
    func dropExited(info: DropInfo) {}
}
