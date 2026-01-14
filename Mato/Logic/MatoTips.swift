import SwiftUI
import TipKit

// MARK: - Tips for Mato features

/// Tip to educate users about Quick Look preview functionality
struct QuickLookTip: Tip {
    var title: Text {
        Text("Preview Files with Quick Look")
    }
    
    var message: Text? {
        Text("Select a file and press Space to preview it instantly without opening the file.")
    }
    
    var image: Image? {
        Image(systemName: "eye.fill")
    }
}

/// Tip to educate users about multi-pane navigation
struct MultiPaneTip: Tip {
    var title: Text {
        Text("Multi-Pane Navigation")
    }
    
    var message: Text? {
        Text("Use multiple panes to view different directories side by side. Add or remove panes using the toolbar controls.")
    }
    
    var image: Image? {
        Image(systemName: "square.split.2x1")
    }
}

/// Tip to educate users about keyboard shortcuts
struct KeyboardShortcutsTip: Tip {
    var title: Text {
        Text("Keyboard Shortcuts")
    }
    
    var message: Text? {
        Text("Use arrow keys to navigate, Space for Quick Look, Return to open files, and Cmd+Click for multi-selection.")
    }
    
    var image: Image? {
        Image(systemName: "keyboard")
    }
}

/// Tip about drag and drop functionality
struct DragDropTip: Tip {
    var title: Text {
        Text("Drag & Drop")
    }
    
    var message: Text? {
        Text("Drag files between panes or folders to move them. Hold Option while dragging to copy instead.")
    }
    
    var image: Image? {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
    }
}

// MARK: - TipKit Configuration

@MainActor
struct MatoTips {
    /// Configure TipKit on app launch
    static func configure() {
        // Configure TipKit
        try? Tips.configure([
            // Reset tips on every launch for testing - remove in production
            .datastoreLocation(.applicationDefault),
            // Display frequency
            .displayFrequency(.immediate)
        ])
    }
    
    /// Reset all tips (useful for testing)
    static func resetTips() {
        try? Tips.resetDatastore()
    }
}
