# Non-Blocking Operations & Smoothness Improvements Guide

## Overview

This guide outlines the improvements made to Mato for better responsiveness and smoothness by making heavy operations non-blocking.

## Key Improvements Implemented

### 1. **Thumbnail Loader Concurrency Control**

**File:** `SimpleThumbnailLoader.swift`

**What was improved:**

- Added **concurrent operation limiting** (max 3 simultaneous thumbnail generations)
- **Deduplication** of in-flight requests (prevents duplicate work for same file)
- **Request tracking** to reuse ongoing operations instead of spawning new ones
- Added batch loading capability with `generateThumbnailsBatch()`

**Benefits:**

- Prevents system overload from too many concurrent QuickLook requests
- Reduces wasted CPU cycles from duplicate requests
- Smoother scrolling with controlled resource usage

**Usage:**

```swift
// Single thumbnail with automatic deduplication
let image = try await thumbnailLoader.generateThumbnail(for: url)

// Batch loading with controlled concurrency
let images = try await thumbnailLoader.generateThumbnailsBatch(for: urls)
```

### 2. **Enhanced ImageIcon Component**

**File:** `ImageIcon.swift`

**What was improved:**

- Uses `.low` task priority for background thumbnail loading
- Maintains task cancellation on disappear
- Doesn't block main thread while loading

**Benefits:**

- Main UI interactions stay responsive
- Grid scrolling remains smooth even while thumbnails load
- View updates are deferred until thumbnails are ready

### 3. **FileManager Service Task Cancellation**

**File:** `FileManagerService.swift`

**What was improved:**

- Added task cancellation tracking for directory operations
- Cancels previous requests when navigating to a new directory
- Added `cancelPendingOperations()` method
- Inserted `Task.checkCancellation()` in loops for responsive cancellation

**Benefits:**

- Stops wasting CPU on old requests when user navigates away
- Faster UI responsiveness during directory browsing
- Reduced memory from abandoned operations

**Usage:**

```swift
// Old requests automatically canceled when loading new directory
viewModel.loadDirectory(at: newURL)

// Manual cancellation if needed
fileManager.cancelPendingOperations(for: directory)
```

### 4. **New VisibilityTracker Utility**

**File:** `VisibilityTracker.swift`

**What it does:**

- Tracks which items are currently visible in the viewport
- Tracks nearby items for intelligent preloading
- Assigns loading priorities based on visibility

**Benefits:**

- Prioritize thumbnails for visible items over off-screen items
- Smart preloading for items entering viewport
- Minimal overhead for invisible items

**Usage:**

```swift
let tracker = VisibilityTracker()

// Update tracker with visible/nearby items
tracker.updateVisibleItems(visibleIDs, nearbyItems: preloadIDs)

// Get appropriate loading priority
let priority = tracker.loadingPriority(for: itemID)

// Use in task spawning
Task(priority: priority) {
    let image = try await loader.generateThumbnail(for: url)
}
```

### 5. **MainThreadGate — Deferred UI Delivery During Scrolling**

**File:** `MainThreadGate.swift`

**What it does:**

- Defers main-actor state updates (like assigning thumbnails) when the run loop is in scroll-tracking mode
- Queues updates during scrolling, flushes them when tracking ends
- Falls back after 0.5s of continuous scrolling to force-flush (prevents stalled thumbnails)

**Benefits:**

- Eliminates view-update storms that cause stuttering during rapid scrolling
- When not scrolling, adds zero overhead — runs inline
- Batches deferred updates into a single flush pass

**How it works:**
The AppKit run loop switches to `.tracking` mode during scroll events.
`MainThreadGate` uses a `CFRunLoopObserver` (`.beforeWaiting`) to detect
when the run loop exits tracking mode. Work submitted via `schedule()` runs
immediately if the thread is free, or is queued if we're in tracking mode.

**Usage:**

```swift
// In any async loading code:
let image = try await loader.generateThumbnail(for: url)
MainThreadGate.shared.schedule {
    self.thumbnail = image
}
```

**Integrated in:**

- `ImageIcon.swift` — thumbnail delivery now goes through `MainThreadGate`

## Architecture Patterns Used

### Task Priorities

- **userInitiated** - Visible item thumbnails (most important)
- **utility** - Nearby items for preloading
- **background** - Off-screen items (lowest priority)
- **low** - Non-critical UI updates during high load

### Concurrency Control

- **Semaphore** - Limits concurrent thumbnail generations to 3
- **In-flight request tracking** - Deduplicates identical requests
- **Task group with maxConcurrentTasks** - Limits batch operations

### Main Thread Backpressure

- **Run-loop mode awareness** — Check `RunLoop.currentMode` to detect scroll tracking
- **CFRunLoopObserver** — Flush queue when run loop exits tracking mode
- **Force-flush timeout** — 0.5s max deferral prevents stalled thumbnails during long scrolls
- **Zero-overhead when idle** — Work runs inline when not tracking

### Cancellation Strategy

- Task cancellation on navigation
- Periodic `Task.checkCancellation()` in loops
- Cleanup of inactive tasks

## Implementation Recommendations

### For Grid/List Views

1. **Integrate VisibilityTracker** to track scroll position
2. **Calculate visible items** during geometry updates
3. **Pass priority** to thumbnail loader based on visibility
4. **Monitor scroll performance** with Xcode Instruments

Example:

```swift
struct DirectoryGridView: View {
    @State private var visibilityTracker = VisibilityTracker()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(items) { item in
                    GridItemView(item: item)
                        .onAppear {
                            visibilityTracker.updateVisibleItems([item.id])
                        }
                        .onDisappear {
                            visibilityTracker.updateVisibleItems([])
                        }
                }
            }
        }
    }
}
```

### For Large Directory Operations

1. **Cancel previous operations** when user navigates
2. **Use batch operations** for multiple items
3. **Monitor Task.checkCancellation()** in loops
4. **Throttle updates** to UI using debouncing

### Performance Monitoring

Use Xcode Instruments to monitor:

- **System Trace** - Thread activity during scrolling
- **Core Animation** - Frame rate during heavy operations
- **Memory** - Cache hit rates and memory usage

## Future Optimizations

1. **Adaptive concurrency** - Adjust max concurrent operations based on system resources
2. **Visibility-based thumbnail generation** - Only load visible item thumbnails
3. **Progressive image loading** - Load low-quality thumbnails first
4. **Caching improvements** - LRU eviction based on visibility
5. **Network optimization** - If adding cloud storage support

## Debugging Tips

### Check Task Cancellation

```swift
// Add logging to see cancellation
private func generateThumbnail(...) async throws -> NSImage {
    do {
        try Task.checkCancellation()
        // ... do work
    } catch is CancellationError {
        print("Thumbnail generation canceled for \(url)")
        throw CancellationError()
    }
}
```

### Monitor Concurrent Operations

```swift
// Add to ThumbnailLoader
private var activeRequests: Int = 0

func generateThumbnail(...) async throws -> NSImage {
    semaphore.wait()
    activeRequests += 1
    print("Active requests: \(activeRequests)")

    defer {
        activeRequests -= 1
        semaphore.signal()
    }
    // ...
}
```

### Profile Main Thread

Use the Main Thread Checker in Xcode to ensure no blocking operations on main thread.

## References

- [Swift Concurrency Documentation](https://developer.apple.com/documentation/swift/concurrency)
- [TaskGroup](https://developer.apple.com/documentation/swift/taskgroup)
- [MainActor](https://developer.apple.com/documentation/swift/mainactor)
- [Dispatch Semaphore](https://developer.apple.com/documentation/dispatch/dispatchsemaphore)
