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
    private let centresURL = URL.cachesDirectory.appending(path: "tile-crop-centres.json")

    private init() {
        centres = (try? Data(contentsOf: centresURL)).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    func cached(_ url: URL) -> Loaded? { memory[url] }

    func load(_ url: URL, salient: Bool) async -> Loaded? {
        if let hit = memory[url] { return hit }
        if let task = inFlight[url] { return await task.value }
        let known = centres[url.lastPathComponent]
        let task = Task<Loaded?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }
            var centre = known.map { CGFloat($0) } ?? 0.5
            if salient, known == nil, let cg = image.cgImage {
                centre = await Self.salientCentreX(cg)
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
        return result
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
