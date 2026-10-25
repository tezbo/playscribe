import UIKit
import Vision

/// D-12: loads tile art and, for landscape key art, finds where to centre the square crop with
/// Vision's attention-based saliency, so faces aren't cut. Run once per image, cached in memory
/// and on disk.
@MainActor
final class TileArtLoader {
    static let shared = TileArtLoader()

    struct Loaded { var image: UIImage; var centreX: CGFloat }

    private var memory: [URL: Loaded] = [:]
    private var inFlight: [URL: Task<Loaded?, Never>] = [:]
    private var centres: [String: Double]
    private let centresURL = URL.cachesDirectory.appending(path: "tile-crop-centres-v2.json")

    private init() {
        centres = (try? Data(contentsOf: centresURL)).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    func cached(_ url: URL) -> Loaded? { memory[url] }

    /// nil when the art can't be used; the caller then shows the cover over a blurred fill.
    func load(_ url: URL, salient: Bool) async -> Loaded? {
        let usable: (Loaded?) -> Loaded? = { ($0?.centreX ?? 0) < 0 ? nil : $0 }
        if let hit = memory[url] { return usable(hit) }
        if centres[url.lastPathComponent].map({ $0 < 0 }) == true { return nil }
        if let task = inFlight[url] { return usable(await task.value) }
        let known = centres[url.lastPathComponent]
        let task = Task<Loaded?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }
            var centre = known.map { CGFloat($0) } ?? 0.5
            if salient, known == nil, let cg = image.cgImage {
                // A concept sheet or other washed-out art is no tile: fall back to the cover.
                centre = Self.isWashedOut(cg) ? -1 : await Self.salientCentreX(cg)
            }
            return Loaded(image: image, centreX: centre)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            memory[url] = result
            if salient && known == nil {
                centres[url.lastPathComponent] = Double(result.centreX)
                if let raw = try? JSONEncoder().encode(centres) { try? raw.write(to: centresURL, options: .atomic) }
            }
        }
        return usable(result)
    }

    /// Mostly white or barely coloured: mean brightness above 0.8 or mean saturation below 0.12.
    nonisolated static func isWashedOut(_ image: CGImage) -> Bool {
        let side = 24
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var brightness = 0.0, saturation = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            brightness += mx
            saturation += mx == 0 ? 0 : (mx - mn) / mx
        }
        let n = Double(side * side)
        return brightness / n > 0.8 || saturation / n < 0.12
    }

    /// Horizontal centre (0...1) of the salient region; 0.5 when Vision finds nothing.
    nonisolated static func salientCentreX(_ image: CGImage) async -> CGFloat {
        let request = GenerateAttentionBasedSaliencyImageRequest()
        guard let observation = try? await request.perform(on: image) else { return 0.5 }
        let boxes = observation.salientObjects.map(\.boundingBox)
        guard let first = boxes.first else { return 0.5 }
        let minX = boxes.map(\.origin.x).reduce(first.origin.x, min)
        let maxX = boxes.map { $0.origin.x + $0.width }.reduce(first.origin.x + first.width, max)
        return CGFloat((minX + maxX) / 2)
    }
}
