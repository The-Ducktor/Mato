import Foundation
import SwiftUI

/// Actor for managing visibility state safely in Swift 6
private actor VisibilityState: Sendable {
    private(set) var visibleItemIDs: Set<UUID> = []
    private(set) var nearbyItemIDs: Set<UUID> = []
    
    func update(visibleItems: Set<UUID>, nearbyItems: Set<UUID>) {
        self.visibleItemIDs = visibleItems
        self.nearbyItemIDs = nearbyItems
    }
    
    func shouldPrioritize(itemID: UUID) -> Bool {
        return visibleItemIDs.contains(itemID)
    }
    
    func shouldPreload(itemID: UUID) -> Bool {
        return nearbyItemIDs.contains(itemID)
    }
    
    func loadingPriority(for itemID: UUID) -> TaskPriority {
        if visibleItemIDs.contains(itemID) {
            return .userInitiated
        } else if nearbyItemIDs.contains(itemID) {
            return .utility
        } else {
            return .background
        }
    }
}

/// Tracks visible items in a scrolling view to optimize thumbnail loading
/// and other heavy operations by prioritizing visible items
@Observable
final class VisibilityTracker: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Items currently visible in the viewport
    private(set) var visibleItemIDs: Set<UUID> = []
    
    /// Items that are about to enter the viewport
    private(set) var nearbyItemIDs: Set<UUID> = []
    
    private nonisolated let visibilityState = VisibilityState()
    
    // MARK: - Methods
    
    /// Update visible items based on scroll position and container bounds
    /// - Parameters:
    ///   - visibleItems: Items in the current viewport
    ///   - nearbyItems: Items near the viewport (for preloading)
    func updateVisibleItems(_ visibleItems: Set<UUID>, nearbyItems: Set<UUID> = []) {
        // Capture values to avoid data race with weak self
        let visibilityState = self.visibilityState
        
        Task.detached {
            await visibilityState.update(visibleItems: visibleItems, nearbyItems: nearbyItems)
            
            await MainActor.run { [weak self] in
                self?.visibleItemIDs = visibleItems
                self?.nearbyItemIDs = nearbyItems
            }
        }
    }
    
    /// Check if an item should be prioritized for loading
    func shouldPrioritize(itemID: UUID) -> Bool {
        // Return cached value for UI layer
        return visibleItemIDs.contains(itemID)
    }
    
    /// Check if an item should be preloaded (nearby)
    func shouldPreload(itemID: UUID) -> Bool {
        return nearbyItemIDs.contains(itemID)
    }
    
    /// Get the priority for a specific item
    func loadingPriority(for itemID: UUID) -> TaskPriority {
        if shouldPrioritize(itemID: itemID) {
            return .userInitiated
        } else if shouldPreload(itemID: itemID) {
            return .utility
        } else {
            return .background
        }
    }
}
