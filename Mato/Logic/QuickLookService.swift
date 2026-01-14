import Foundation
@preconcurrency import Quartz
import AppKit

/// Service to handle Quick Look previews using QLPreviewPanel
@MainActor
final class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookService()
    
    // Use nonisolated(unsafe) since these are accessed from protocol methods
    // that can be called from any thread, but in practice QLPreviewPanel
    // only calls them from the main thread
    nonisolated(unsafe) private var previewURLs: [URL] = []
    nonisolated(unsafe) private var currentIndex: Int = 0
    
    private override init() {
        super.init()
    }
    
    /// Show Quick Look preview for the given URLs
    func showPreview(for urls: [URL], startingAt index: Int = 0) {
        guard !urls.isEmpty else { return }
        
        self.previewURLs = urls
        self.currentIndex = index
        
        // Get the shared preview panel
        guard let panel = QLPreviewPanel.shared() else { return }
        
        // Set ourselves as the data source and delegate
        panel.dataSource = self
        panel.delegate = self
        
        // Update to the current index
        panel.currentPreviewItemIndex = index
        
        // Make the panel key and order front
        panel.makeKeyAndOrderFront(nil)
    }
    
    /// Toggle Quick Look preview visibility
    func togglePreview() {
        guard let panel = QLPreviewPanel.shared() else { return }
        
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    // MARK: - QLPreviewPanelDataSource
    
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewURLs.count
    }
    
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0 && index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }
    
    // MARK: - QLPreviewPanelDelegate
    
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Allow the panel to handle keyboard events
        return false
    }
    
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        // Return the frame for animation - can be customized based on selected item
        return NSRect.zero
    }
}
