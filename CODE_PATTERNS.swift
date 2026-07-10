import Foundation

// MARK: - Non-Blocking Code Patterns

// ============================================================================
// PATTERN 1: Proper Task Cancellation on Navigation
// ============================================================================

/// Example of handling task cancellation during directory navigation
func navigateWithProperCancellation() {
    // Before: Old operations might still run
    // viewModel.loadDirectory(at: newURL)
    
    // After: Previous operations are canceled automatically
    fileManager.cancelPendingOperations(for: oldURL)  // Optional explicit cleanup
    viewModel.loadDirectory(at: newURL)  // This auto-cancels old tasks internally
}

// ============================================================================
// PATTERN 2: Priority-Based Thumbnail Loading
// ============================================================================

/// Load thumbnails with intelligent prioritization
func loadThumbnailWithPriority(itemID: UUID, priority: TaskPriority) {
    Task(priority: priority) {
        do {
            let image = try await loader.generateThumbnail(for: url)
            await MainActor.run {
                updateUI(with: image)
            }
        } catch is CancellationError {
            // Silently handle cancellation
        } catch {
            // Handle other errors
        }
    }
}

// Usage:
// For visible items: loadThumbnailWithPriority(itemID, priority: .userInitiated)
// For nearby items: loadThumbnailWithPriority(itemID, priority: .utility)
// For distant items: loadThumbnailWithPriority(itemID, priority: .background)

// ============================================================================
// PATTERN 3: Batch Operations with Controlled Concurrency
// ============================================================================

/// Load multiple thumbnails efficiently
func loadMultipleThumbnailsEfficiently(urls: [URL]) {
    Task {
        do {
            // This automatically limits concurrency to 3 operations
            let thumbnails = try await loader.generateThumbnailsBatch(for: urls)
            
            for (url, image) in thumbnails {
                // Update UI for each thumbnail
                updateItemUI(for: url, with: image)
            }
        } catch {
            print("Error loading thumbnails: \(error)")
        }
    }
}

// ============================================================================
// PATTERN 4: Cancellation in Long-Running Loops
// ============================================================================

/// Example of properly handling cancellation in background operations
func processLargeDirectoryWithCancellation() {
    Task.detached(priority: .userInitiated) {
        for item in hugeList {
            // This allows quick cancellation without waiting for loop to finish
            try Task.checkCancellation()
            
            // Do work for this item
            processItem(item)
        }
    }
}

// ============================================================================
// PATTERN 5: Deferred UI Updates for Smoothness
// ============================================================================

/// Load data in background, batch update UI to avoid jank
@MainActor
func deferredUIUpdates() {
    var items: [DirectoryItem] = []
    
    Task.detached(priority: .userInitiated) {
        // Load on background thread
        let loadedItems = try await fileManager.getContents(of: directory)
        
        // Update UI on main thread in batch
        await MainActor.run {
            self.items = loadedItems
        }
    }
}

// ============================================================================
// PATTERN 6: Smart Visibility-Based Loading
// ============================================================================

/// Load only visible items first, preload nearby, ignore distant
func smartVisibilityLoading(visibleItems: Set<UUID>, nearbyItems: Set<UUID>) {
    for itemID in visibleItems {
        // Highest priority - load immediately
        Task(priority: .userInitiated) {
            // Load this item
        }
    }
    
    for itemID in nearbyItems {
        // Medium priority - preload for smooth scrolling
        Task(priority: .utility) {
            // Load this item
        }
    }
    
    // Off-screen items get lowest priority or are skipped entirely
}

// ============================================================================
// PATTERN 7: Preventing Duplicate Work
// ============================================================================

/// The ThumbnailLoader now prevents this automatically, but here's the concept:
class SmartCache {
    private var inFlightRequests: [URL: Task<Result<NSImage, Error>, Never>] = [:]
    
    func getThumbnail(for url: URL) async -> Result<NSImage, Error> {
        // Check if already loading this exact thumbnail
        if let existingTask = inFlightRequests[url] {
            return await existingTask.value
        }
        
        // Create new request
        let task = Task {
            // ... do work
            return .success(image)
        }
        
        inFlightRequests[url] = task
        return await task.value
    }
}

// ============================================================================
// PATTERN 8: Responsive UI During Heavy Operations
// ============================================================================

/// Keep UI responsive while loading large amounts of data
struct ResponsiveLoadingExample {
    
    @State private var items: [Item] = []
    @State private var isLoading = false
    
    var body: some View {
        List {
            ForEach(items) { item in
                ItemRow(item: item)
            }
        }
        .task {
            isLoading = true
            
            // Load on background thread with .utility priority
            let loaded = try await Task.detached(priority: .utility) {
                return try await fileManager.getContents(of: directory)
            }.value
            
            // Update UI
            self.items = loaded
            isLoading = false
        }
    }
}

// ============================================================================
// PATTERN 9: Progress Reporting Without Blocking
// ============================================================================

/// Report progress while loading without blocking UI
@MainActor
func progressiveLoading() {
    @State var progress: Double = 0
    @State var total: Int = 0
    
    Task.detached(priority: .utility) {
        let items = try await fileManager.getContents(of: directory)
        var loaded = 0
        
        for item in items {
            try Task.checkCancellation()
            processItem(item)
            loaded += 1
            
            // Update progress on main thread
            await MainActor.run {
                progress = Double(loaded) / Double(items.count)
            }
        }
    }
}

// ============================================================================
// PATTERN 10: Graceful Degradation
// ============================================================================

/// Load full thumbnails, fall back to icons if cancellation occurs
func gracefulLoadingFallback() async {
    do {
        // Try to load full thumbnail
        let thumbnail = try await loader.generateThumbnail(for: url)
        showFullThumbnail(thumbnail)
        
    } catch is CancellationError {
        // If canceled, show quick icon instead
        let icon = cachedWorkspaceIcon(for: url)
        showQuickIcon(icon)
        
    } catch {
        // On error, show default
        showDefaultIcon()
    }
}

// ============================================================================
// IMPORTANT REMINDERS
// ============================================================================

/*
 
 KEY POINTS FOR NON-BLOCKING OPERATIONS:
 
 1. ALWAYS CHECK CANCELLATION in loops:
    try Task.checkCancellation()
 
 2. USE APPROPRIATE TASK PRIORITIES:
    .userInitiated  - Visible/critical work
    .utility        - Background work that's nice to have
    .background     - Low priority tasks
 
 3. UPDATE UI ON MAIN THREAD:
    await MainActor.run { self.updateUI() }
 
 4. LIMIT CONCURRENT OPERATIONS:
    Use TaskGroup with maxConcurrentTasks or Semaphore
 
 5. CANCEL OLD TASKS WHEN NAVIGATING:
    The system does this, but you can be explicit:
    fileManager.cancelPendingOperations(for: directory)
 
 6. DEDUPLICATE REQUESTS:
    The ThumbnailLoader does this automatically
 
 7. USE @UNCHECKED SENDABLE CAREFULLY:
    Only when you're sure data is thread-safe
 
 8. MONITOR WITH INSTRUMENTS:
    System Trace, Core Animation, Memory tools
 
 9. NEVER BLOCK THE MAIN THREAD:
    Do heavy work in Task.detached or Task with priority
 
 10. PROVIDE FALLBACKS:
     Always handle cancellation and errors gracefully
 
 */
