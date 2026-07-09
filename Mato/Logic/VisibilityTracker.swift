import Foundation
import SwiftUI

/// Tracks visible items in a scrolling view to optimize thumbnail loading
/// and other heavy operations by prioritizing visible items.
///
/// Note: Currently unused — kept for future scroll-performance integration.
@Observable
final class VisibilityTracker: @unchecked Sendable {
    
    /// Items currently visible in the viewport
    private(set) var visibleItemIDs: Set<UUID> = []
    
    /// Items that are about to enter the viewport
    private(set) var nearbyItemIDs: Set<UUID> = []
    
    /// Update visible items based on scroll position and container bounds.
    /// Updates are applied directly on the main actor since this is only
    /// called from UI observation callbacks which are already on the main thread.
    func updateVisibleItems(_ visibleItems: Set<UUID>, nearbyItems: Set<UUID> = []) {
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
        if shouldPrioritize(itemID: itemID) {
            return .userInitiated
        } else if shouldPreload(itemID: itemID) {
            return .utility
        } else {
            return .background
        }
    }
}
