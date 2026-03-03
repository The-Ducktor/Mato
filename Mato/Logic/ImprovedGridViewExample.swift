import SwiftUI

/// Example implementation showing how to integrate visibility tracking
/// for improved scrolling performance in a large grid view
struct ImprovedGridViewExample: View {
    var items: [DirectoryItem]
    
    @State private var visibilityTracker = VisibilityTracker()
    @State private var scrollOffset: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    
    let thumbnailLoader = SimpleThumbnailLoader()
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120))], spacing: 16) {
                    ForEach(items, id: \.id) { item in
                        VStack {
                            // Example: Load thumbnail with priority based on visibility
                            SmartThumbnailView(
                                item: item,
                                loader: thumbnailLoader,
                                priority: visibilityTracker.loadingPriority(for: item.id)
                            )
                            
                            Text(item.name)
                                .lineLimit(2)
                                .font(.caption)
                        }
                        .frame(height: 120)
                        .id(item.id)
                    }
                }
                .padding()
                .onPreferenceChange(VisibleItemPreferenceKey.self) { visibleIDs in
                    // Update tracker with currently visible items
                    visibilityTracker.updateVisibleItems(visibleIDs)
                }
                .background(
                    // Inject visibility tracking
                    ForEach(items, id: \.id) { item in
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: VisibleItemPreferenceKey.self,
                                value: isVisible(geo, in: geometry) ? [item.id] : []
                            )
                        }
                        .frame(height: 0)
                    }
                )
            }
            .onAppear {
                containerHeight = geometry.size.height
            }
        }
    }
    
    private func isVisible(_ itemGeo: GeometryProxy, in containerGeo: GeometryProxy) -> Bool {
        let itemFrame = itemGeo.frame(in: .global)
        let containerFrame = containerGeo.frame(in: .global)
        
        // Consider visible if item overlaps container by more than 20%
        return itemFrame.intersects(containerFrame)
    }
}

/// Specialized view that handles thumbnail loading with intelligent prioritization
struct SmartThumbnailView: View {
    let item: DirectoryItem
    let loader: SimpleThumbnailLoader
    let priority: TaskPriority
    
    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Color.gray.opacity(0.1)
                    if isLoading {
                        ProgressView()
                    }
                }
            }
        }
        .task(id: item.id) {
            await loadWithPriority()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
    private func loadWithPriority() async {
        guard !item.isDirectory && !item.isTextBasedFile else { return }
        
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                let options = SimpleThumbnailLoader.ThumbnailOptions(
                    size: CGSize(width: 100, height: 100),
                    scale: 2.0,
                    maintainAspectRatio: true
                )
                
                try Task.checkCancellation()
                let loaded = try await loader.generateThumbnail(
                    for: item.url,
                    options: options
                )
                
                try Task.checkCancellation()
                await MainActor.run {
                    self.thumbnail = loaded
                }
            } catch is CancellationError {
                // Task was canceled, silently ignore
            } catch {
                // Keep default appearance on error
            }
        }
    }
}

// MARK: - Preference Key for Visibility Tracking

struct VisibleItemPreferenceKey: PreferenceKey {
    static let defaultValue: Set<UUID> = []
    
    static func reduce(value: inout Set<UUID>, nextValue: () -> Set<UUID>) {
        value.formUnion(nextValue())
    }
}

// MARK: - Example with DirectoryGridView Integration

extension DirectoryGridView {
    /// Example of how to integrate visibility tracking into existing grid
    func integrateVisibilityTracking() {
        // 1. Add @State property:
        // @State private var visibilityTracker = VisibilityTracker()
        
        // 2. Wrap items in GeometryReader to track visibility:
        // ForEach(viewModel.sortedItems) { item in
        //     GeometryReader { geo in
        //         GridItemView(item: item, ...)
        //             .onAppear {
        //                 if isVisible(geo) {
        //                     visibilityTracker.updateVisibleItems([item.id])
        //                 }
        //             }
        //     }
        // }
        
        // 3. Pass priority when loading thumbnails:
        // let priority = visibilityTracker.loadingPriority(for: item.id)
        // Task(priority: priority) {
        //     let image = try await loader.generateThumbnail(for: item.url)
        // }
    }
}
