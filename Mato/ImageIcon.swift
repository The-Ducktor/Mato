//
//  ImageIcon.swift
//  Mato
//
//  Created by Jackson Powell on 5/24/25.
//

import SwiftUI
import AppKit
import QuickLookThumbnailing

struct ImageIcon: View {
    
    @Binding var item: DirectoryItem
    @State private var previewImage: Bool = true // Set to true to enable thumbnails
    @State private var thumbnail: NSImage?
    @State private var isLoading: Bool = false

    private var image: NSImage {
        if previewImage, let thumbnail = thumbnail {
            return thumbnail
        } else {
            return NSWorkspace.shared.icon(forFile: item.url.path)
        }
    }

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .id(thumbnail) // Force redraw when thumbnail updates
            
            
            
        }
        
    }
}
