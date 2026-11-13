import SwiftUI
import UIKit
import ImageIO

/// Library scroll lag fix: cover art for tiles.
/// `AsyncImage` kept no image once its cell left the lazy grid, so scrolling back re-fetched and re-decoded the full 528 x 748 JPEG on every
/// re-entry. This keeps a small, already-decoded copy per cover in memory (decoded off the main thread at the size the tile needs), so a
/// tile that comes back on screen draws at once with no decode.
@MainActor
final class CoverImageCache {
    static let shared = CoverImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() { cache.countLimit = 160 }

    private func key(_ url: URL, _ maxPixel: Int) -> String { "\(maxPixel)|\(url.absoluteString)" }

    /// The decoded cover if it is already in memory.
    func cached(_ url: URL, maxPixel: Int) -> UIImage? { cache.object(forKey: key(url, maxPixel) as NSString) }

    func load(_ url: URL, maxPixel: Int) async -> UIImage? {
        let k = key(url, maxPixel)
        if let hit = cache.object(forKey: k as NSString) { return hit }
        if let task = inFlight[k] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }
        inFlight[k] = task
        let image = await task.value
        inFlight[k] = nil
        if let image { cache.setObject(image, forKey: k as NSString) }
        return image
    }

    /// Decodes straight to a thumbnail no larger than `maxPixel` on its longest side, fully decoded here (not lazily on first draw).
    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A cover image drawn from `CoverImageCache`: a cached one shows on the first frame, with no fade; a new one fades in.
struct CachedCoverImage: View {
    var url: URL
    var maxPixel: Int
    @State private var image: UIImage?

    init(url: URL, maxPixel: Int) {
        self.url = url
        self.maxPixel = maxPixel
        _image = State(initialValue: CoverImageCache.shared.cached(url, maxPixel: maxPixel))
    }

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
        }
        .task(id: url) {
            if let hit = CoverImageCache.shared.cached(url, maxPixel: maxPixel) { image = hit; return }
            let loaded = await CoverImageCache.shared.load(url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
