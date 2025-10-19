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
        let maintainAspectRatio: Bool
        
        init(size: CGSize = CGSize(width: 256, height: 256), scale: CGFloat = 2.0, maintainAspectRatio: Bool = true) {
            self.size = size
            self.scale = scale
            self.maintainAspectRatio = maintainAspectRatio
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
            // Use .icon to prevent cropping and maintain aspect ratio
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: options.size,
                scale: options.scale,
                representationTypes: .all
            )
            
            thumbnailGenerator.generateBestRepresentation(for: request) { representation, error in
                // Extract Sendable data off-actor to avoid sending non-Sendable representation across actors
                let cgImage = representation?.cgImage
                let imageWidth = cgImage.map { CGFloat($0.width) }
                let imageHeight = cgImage.map { CGFloat($0.height) }

                Task { @MainActor in
                    if let cgImage, let imageWidth, let imageHeight {
                        // Calculate the final size to fit within bounds while maintaining aspect ratio
                        let finalSize: CGSize
                        if options.maintainAspectRatio {
                            let aspectRatio = imageWidth / imageHeight
                            let targetAspectRatio = options.size.width / options.size.height
                            
                            if aspectRatio > targetAspectRatio {
                                // Image is wider - fit to width
                                finalSize = CGSize(width: options.size.width, height: options.size.width / aspectRatio)
                            } else {
                                // Image is taller - fit to height
                                finalSize = CGSize(width: options.size.height * aspectRatio, height: options.size.height)
                            }
                        } else {
                            finalSize = CGSize(width: imageWidth, height: imageHeight)
                        }
                        
                        let nsImage = NSImage(cgImage: cgImage, size: finalSize)
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

