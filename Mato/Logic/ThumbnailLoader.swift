import Foundation
@preconcurrency import QuickLookThumbnailing
import AppKit
import Observation

/// Actor to manage semaphore-based concurrency limits in Swift 6
private actor ConcurrencyLimiter: Sendable {
    private let maxConcurrent: Int
    private var currentCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(maxConcurrent: Int = 3) {
        self.maxConcurrent = maxConcurrent
    }
    
    func acquire() async {
        while currentCount >= maxConcurrent {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        currentCount += 1
    }
    
    func release() {
        currentCount -= 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}

/// Actor to manage in-flight requests safely in Swift 6
private actor RequestDeduplicator: Sendable {
    private var inFlightRequests: [URL: Task<NSImage, Error>] = [:]
    
    func getExistingTask(for url: URL) -> Task<NSImage, Error>? {
        return inFlightRequests[url]
    }
    
    func setTask(_ task: Task<NSImage, Error>, for url: URL) {
        inFlightRequests[url] = task
    }
    
    func removeTask(for url: URL) {
        inFlightRequests.removeValue(forKey: url)
    }
}

@Observable
final class SimpleThumbnailLoader: @unchecked Sendable {
    
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
    
    // NSCache is thread-safe, so we can use @unchecked Sendable
    private let thumbnailGenerator = QLThumbnailGenerator.shared
    private let imageCache = NSCache<NSURL, NSImage>()
    
    // In-flight requests to prevent duplicate work (Swift 6 safe)
    private nonisolated let deduplicator = RequestDeduplicator()
    
    // Concurrent operations limit using actor instead of semaphore
    private nonisolated let concurrencyLimiter = ConcurrencyLimiter(maxConcurrent: 3)
    
    // MARK: - Initialization
    
    init() {
        setupCache()
    }
    
    private func setupCache() {
        imageCache.countLimit = 500 // Increased for better caching
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Public Methods
    
    /// Generate a thumbnail using QuickLook with deduplication and priority handling
    func generateThumbnail(for url: URL, options: ThumbnailOptions = ThumbnailOptions()) async throws -> NSImage {
        guard url.isFileURL else {
            throw ThumbnailError.invalidURL
        }
        
        // Check cache first
        if let cachedImage = imageCache.object(forKey: url as NSURL) {
            return cachedImage
        }
        
        // Check for in-flight request to avoid duplicate work
        if let existingTask = await deduplicator.getExistingTask(for: url) {
            return try await existingTask.value
        }
        
        // Create a new request task
        let requestTask = Task<NSImage, Error> {
            defer {
                Task.detached {
                    await self.deduplicator.removeTask(for: url)
                }
            }
            
            // Limit concurrent operations using actor
            await self.concurrencyLimiter.acquire()
            defer {
                Task.detached {
                    await self.concurrencyLimiter.release()
                }
            }
            
            let thumbnail = try await self.generateQuickLookThumbnail(for: url, options: options)
            self.imageCache.setObject(thumbnail, forKey: url as NSURL)
            return thumbnail
        }
        
        // Store the in-flight request
        await deduplicator.setTask(requestTask, for: url)
        
        return try await requestTask.value
    }
    
    /// Generate thumbnails in batch with priority handling
    func generateThumbnailsBatch(for urls: [URL], options: ThumbnailOptions = ThumbnailOptions()) async throws -> [URL: NSImage] {
        var results: [URL: NSImage] = [:]
        
        try await withThrowingTaskGroup(of: (URL, NSImage).self) { group in
            for url in urls {
                try group.addTask {
                    let image = try await self.generateThumbnail(for: url, options: options)
                    return (url, image)
                }
            }
            
            for try await (url, image) in group {
                results[url] = image
            }
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func generateQuickLookThumbnail(for url: URL, options: ThumbnailOptions) async throws -> NSImage {
        return try await withCheckedThrowingContinuation { continuation in
            // Use .thumbnail with .icon fallback for optimal performance
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: options.size,
                scale: options.scale,
                representationTypes: [.thumbnail, .icon]
            )
            
            thumbnailGenerator.generateBestRepresentation(for: request) { representation, error in
                // Process on background thread
                if let cgImage = representation?.cgImage {
                    let imageWidth = CGFloat(cgImage.width)
                    let imageHeight = CGFloat(cgImage.height)
                    
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
    
    // MARK: - Cache Management
    
    func clearCache() {
        imageCache.removeAllObjects()
    }
    
    func removeCachedThumbnail(for url: URL) {
        imageCache.removeObject(forKey: url as NSURL)
    }
}

