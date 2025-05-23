import Foundation
import AppKit
import QuickLookThumbnailing

class ThumbnailLoader: ObservableObject {
    @Published var thumbnails: [URL: NSImage] = [:]
    private let generator = QLThumbnailGenerator.shared

    /// Get thumbnail for URL, scaling to fit within either maxWidth or maxHeight, whichever is more restrictive.
    /// - Parameters:
    ///   - url: The file URL.
    ///   - maxWidth: The maximum width for the resulting thumbnail.
    ///   - maxHeight: The maximum height for the resulting thumbnail.
    /// - Returns: The NSImage for the thumbnail, or nil if not yet loaded.
    func thumbnail(for url: URL, maxWidth: CGFloat = 64, maxHeight: CGFloat = 64) -> NSImage? {
        if let image = thumbnails[url] {
            return image
        }
        generateThumbnail(for: url, maxWidth: maxWidth, maxHeight: maxHeight)
        return nil // Will cause the view to update when loaded
    }

    private func generateThumbnail(for url: URL, maxWidth: CGFloat, maxHeight: CGFloat) {
        // First, request a thumbnail at a large size to get the original aspect ratio.
        // We use 1024x1024 as a "safe" big size.
        let originalRequestSize = CGSize(width: 128, height: 128)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: originalRequestSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        generator.generateBestRepresentation(for: request) { [weak self] (thumbnail, error) in
            guard let self = self, let cgImage = thumbnail?.cgImage else { return }
            let originalWidth = CGFloat(cgImage.width)
            let originalHeight = CGFloat(cgImage.height)

            // Calculate aspect-fit size within maxWidth/maxHeight
            let widthRatio = maxWidth / originalWidth
            let heightRatio = maxHeight / originalHeight
            let scale = min(widthRatio, heightRatio, 1.0) // never upscale

            // Round to integers to avoid fractional pixel dimensions
            let finalWidth = round(originalWidth * scale)
            let finalHeight = round(originalHeight * scale)
            let finalSize = CGSize(width: finalWidth, height: finalHeight)

            // Generate the thumbnail at the correct size
            let sizedRequest = QLThumbnailGenerator.Request(
                fileAt: url,
                size: finalSize,
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .all
            )
            self.generator.generateBestRepresentation(for: sizedRequest) { [weak self] (sizedThumbnail, error) in
                guard let cgImageSized = sizedThumbnail?.cgImage else { return }
                let image = NSImage(cgImage: cgImageSized, size: finalSize)
                DispatchQueue.main.async {
                    self?.thumbnails[url] = image
                }
            }
        }
    }
}
