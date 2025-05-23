import Foundation
import AppKit
import QuickLookThumbnailing

class ThumbnailLoader: ObservableObject {
    @Published var thumbnails: [ThumbnailKey: NSImage] = [:]

    private let generator = QLThumbnailGenerator.shared
    private let memoryCache = NSCache<NSString, NSImage>()
    private var pendingRequests: Set<ThumbnailKey> = []

    struct ThumbnailKey: Hashable {
        let url: URL
        let maxSize: CGSize
        
        // Use maxSize instead of exact size since we'll preserve aspect ratio
        init(url: URL, maxSize: CGSize) {
            self.url = url
            self.maxSize = maxSize
        }
    }

    func thumbnail(for url: URL, maxWidth: CGFloat = 64, maxHeight: CGFloat = 64) -> NSImage? {
        let maxSize = CGSize(width: maxWidth, height: maxHeight)
        let key = ThumbnailKey(url: url, maxSize: maxSize)
        let cacheKey = self.cacheKey(for: key)

        // 1. Memory Cache
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // 2. Published In-Memory Store
        if let image = thumbnails[key] {
            return image
        }

        // 3. Disk Cache
        if let diskImage = loadFromDisk(for: key) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            thumbnails[key] = diskImage
            return diskImage
        }

        // 4. Generate Thumbnail (async)
        generateThumbnail(for: key)

        return nil
    }

    private func generateThumbnail(for key: ThumbnailKey) {
        guard !pendingRequests.contains(key) else { return }
        pendingRequests.insert(key)

        // Use the maximum dimension to ensure we get enough resolution
        // while letting QuickLook handle the aspect ratio
        let maxDimension = max(key.maxSize.width, key.maxSize.height)
        let requestSize = CGSize(width: maxDimension, height: maxDimension)

        let request = QLThumbnailGenerator.Request(
            fileAt: key.url,
            size: requestSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        generator.generateBestRepresentation(for: request) { [weak self] thumbnail, error in
            guard let self = self else { return }
            defer { self.pendingRequests.remove(key) }

            guard let cgImage = thumbnail?.cgImage else { return }

            // Get the actual size from the generated thumbnail
            let actualSize = CGSize(width: cgImage.width, height: cgImage.height)
            
            // Calculate the size that fits within our bounds while preserving aspect ratio
            let scaledSize = self.calculateScaledSize(originalSize: actualSize, maxSize: key.maxSize)
            
            // Create the image with the actual thumbnail size
            // NSImage will handle the display scaling appropriately
            let image = NSImage(cgImage: cgImage, size: scaledSize)
            let cacheKey = self.cacheKey(for: key)

            // Save to memory, disk, and update UI
            self.memoryCache.setObject(image, forKey: cacheKey)
            self.saveToDisk(image: image, for: key)

            DispatchQueue.main.async {
                self.thumbnails[key] = image
            }
        }
    }

    // Calculate the size that fits within maxSize while preserving aspect ratio
    private func calculateScaledSize(originalSize: CGSize, maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let scale = min(widthRatio, heightRatio)
        
        return CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
    }

    // MARK: - Disk Cache

    private func diskCacheURL(for key: ThumbnailKey) -> URL {
        let name = "\(key.url.path)_\(Int(key.maxSize.width))x\(Int(key.maxSize.height))"
        let hashed = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "thumb"
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(hashed).png")
    }

    private func saveToDisk(image: NSImage, for key: ThumbnailKey) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? pngData.write(to: diskCacheURL(for: key))
    }

    private func loadFromDisk(for key: ThumbnailKey) -> NSImage? {
        let url = diskCacheURL(for: key)
        return NSImage(contentsOf: url)
    }

    // MARK: - Cache Key

    private func cacheKey(for key: ThumbnailKey) -> NSString {
        "\(key.url.absoluteString)_\(Int(key.maxSize.width))x\(Int(key.maxSize.height))" as NSString
    }
}
