//
//  MainThreadGate.swift
//  Mato
//
//  Created on 11/5/25.
//

import Foundation

/// Schedules main-actor work to run only when the main thread is *free* —
/// specifically, when the run loop is **not** in scroll‑tracking mode.
///
/// During scrolling, updates are queued and flushed once tracking ends,
/// preventing view‑update storms that cause stuttering.
///
/// ## Why this works
/// When the user scrolls, AppKit switches the main run loop into
/// ``RunLoop.Mode.eventTracking``. Any state assignment delivered during
/// tracking forces SwiftUI to re‑render *while* the scroll view is
/// trying to composite frames → dropped frames.
///
/// ``MainThreadGate`` checks the current run‑loop mode. If it's tracking,
/// the update is deferred to a queue. A ``CFRunLoopObserver`` set on
/// ``.beforeWaiting`` fires at the end of each run‑loop pass and flushes
/// the queue — but only when the mode is back to ``.default`` (i.e.
/// scrolling has stopped).
///
/// ## Usage
/// ```swift
/// let image = try await thumbnailLoader.generateThumbnail(for: url)
/// MainThreadGate.shared.schedule {
///     self.thumbnail = image
/// }
/// ```
///
/// - Note: If no scrolling occurs, the work runs synchronously inline,
///   adding zero overhead. The gate only intervenes during scroll tracking.
final class MainThreadGate: @unchecked Sendable {
    static let shared = MainThreadGate()

    // MARK: - Constants

    /// If scrolling lasts longer than this, the gate force‑flushes even
    /// during tracking so thumbnails don't stay blank indefinitely.
    private static let maxDeferInterval: TimeInterval = 0.5

    // MARK: - State

    private let lock = NSLock()
    private var pendingWork: [() -> Void] = []
    private var observer: CFRunLoopObserver?
    private var lastFlushTime: Date = .distantPast

    // MARK: - Init

    private init() {
        observer = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,   // repeats
            0
        ) { [weak self] _, _ in
            guard let self else { return }

            // Flush only when we're not in scroll-tracking mode, OR
            // if we've been deferring too long (prevent stall).
            let isTracking = RunLoop.main.currentMode == .eventTracking
            let forceFlush = Date().timeIntervalSince(lastFlushTime) >= Self.maxDeferInterval
            if !isTracking || forceFlush {
                flush()
            }
        }

        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    // MARK: - Public API

    /// Schedule a block to run on the main thread, but only when it's free.
    ///
    /// - If called from the main thread **and** the run loop is not tracking,
    ///   the block runs **immediately** — zero overhead.
    /// - If called during scroll tracking (or from a background queue), the
    ///   block is queued and delivered when tracking ends.
    func schedule(_ work: @escaping () -> Void) {
        if Thread.isMainThread, RunLoop.current.currentMode != .eventTracking {
            // Main thread is free — run now.
            work()
            return
        }

        // Queue it for later delivery.
        lock.withLock {
            pendingWork.append(work)
        }

        // Wake the run loop so our observer fires promptly.
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    // MARK: - Flush

    private func flush() {
        lastFlushTime = Date()

        let batch: [() -> Void] = lock.withLock {
            let items = pendingWork
            pendingWork = []
            return items
        }

        for work in batch {
            work()
        }
    }

    deinit {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }
}
