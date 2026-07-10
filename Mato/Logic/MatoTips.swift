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

// MARK: - TipKit Configuration

@MainActor
struct MatoTips {
    /// Configure TipKit on app launch
    static func configure() {
        try? Tips.configure([
            .datastoreLocation(.applicationDefault),
            .displayFrequency(.monthly)
        ])
    }
    
    /// Reset all tips (useful for testing)
    static func resetTips() {
        try? Tips.resetDatastore()
    }
}
