import Foundation
@preconcurrency import QuickLookThumbnailing
import AppKit

@MainActor
final class SimpleThumbnailLoader: ObservableObject {
    
    // MARK: - Types
    
    enum ThumbnailError: Error, LocalizedError {
        case thumbnailGenerationFailed
        case invalidURL
        
        var errorDescription: String? {
            switch self {
            case .thumbnailGenerationFailed:
                return "Failed to generate thumbnail"
            case .invalidURL:
                return "Invalid file URL"
            }
        }
    }
    
    struct ThumbnailOptions: Sendable {
        let size: CGSize
        let scale: CGFloat
        
        init(size: CGSize = CGSize(width: 256, height: 256), scale: CGFloat = 2.0) {
            self.size = size
            self.scale = scale
        }
    }
    
    // MARK: - Properties
    
    private let thumbnailGenerator = QLThumbnailGenerator.shared
    private let imageCache = NSCache<NSURL, NSImage>()
    
    // MARK: - Initialization
    
    init() {
        setupCache()
    }
    
    private func setupCache() {
        imageCache.countLimit = 100
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    // MARK: - Public Methods
    
    /// Generate a thumbnail using QuickLook
    func generateThumbnail(for url: URL, options: ThumbnailOptions = ThumbnailOptions()) async throws -> NSImage {
        guard url.isFileURL else {
            throw ThumbnailError.invalidURL
        }
        
        // Check cache first
        if let cachedImage = imageCache.object(forKey: url as NSURL) {
            return cachedImage
        }
        
        let thumbnail = try await generateQuickLookThumbnail(for: url, options: options)
        imageCache.setObject(thumbnail, forKey: url as NSURL)
        return thumbnail
    }
    
    // MARK: - Private Methods
    
    private func generateQuickLookThumbnail(for url: URL, options: ThumbnailOptions) async throws -> NSImage {
        return try await withCheckedThrowingContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: options.size,
                scale: options.scale,
                representationTypes: .all
            )
            
            thumbnailGenerator.generateBestRepresentation(for: request) { representation, error in
                Task { @MainActor in
                    if let representation = representation {
                        let nsImage = NSImage(cgImage: representation.cgImage, size: options.size)
                        continuation.resume(returning: nsImage)
                    } else {
                        continuation.resume(throwing: error ?? ThumbnailError.thumbnailGenerationFailed)
                    }
                }
            }
        }
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        imageCache.removeAllObjects()
    }
    
    func removeCachedThumbnail(for url: URL) {
        imageCache.removeObject(forKey: url as NSURL)
    }
}
