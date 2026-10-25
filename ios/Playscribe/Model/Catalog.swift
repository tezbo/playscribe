import Foundation

enum OwnershipStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case owned, wishlist, watching
    var id: String { rawValue }
    var label: String {
        switch self {
        case .owned: "Owned"
        case .wishlist: "Wishlist"
        case .watching: "Watching"
        }
    }
}

enum NotifyLevel: String, Codable, CaseIterable, Hashable, Identifiable {
    case all, major, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All updates"
        case .major: "Major only"
        case .off: "Off"
        }
    }
}

enum Coverage: String, Codable, Hashable { case full, partial, none }

struct CatalogGame: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var developer: String?
    var publisher: String?
    var platforms: [Platform]
    var releaseDate: String?
    /// Earlier PS4 release date for games playable on PS5 before their PS5 release.
    var playableSince: String?
    var igdbID: Int?
    /// Bundled artwork in the asset catalogue.
    var coverAsset: String?
    var heroAsset: String?
    var featureAsset: String?
    /// IGDB image id for covers served from the IGDB CDN.
    var coverImageID: String?
    var tones: [String]?
    var coverage: Coverage
    /// Backdrop artwork per chapter: [wide, tall].
    var chapterArt: [String: [String]]?
    /// Added by the person: no catalogue record behind it.
    var custom: Bool?

    var coverURL: URL? {
        coverImageID.map { URL(string: "https://images.igdb.com/igdb/image/upload/t_cover_big_2x/\($0).jpg")! }
    }

    /// The PS5 launched on 12 Nov 2020; no "on PS5" date can be earlier.
    static let ps5Launch = "2020-11-12".isoDay!

    /// The date line for a catalogue game: its native PS5 release, else when it became playable
    /// on PS5 through its PS4 version. Dates before the PS5 launch are never shown.
    var ps5DateLine: String? {
        let launch = Self.ps5Launch
        if let d = releaseDate?.isoDay, d >= launch, playableSince.flatMap(\.isoDay).map({ $0 >= launch && $0 < d }) != true {
            return "Released \(d.shortDay)"
        }
        if let b = playableSince?.isoDay {
            return b >= launch ? "Playable on PS5 since \(b.formatted(.dateTime.month(.abbreviated).year()))" : "Plays on PS5 (PS4 version)"
        }
        if let d = releaseDate?.isoDay, d < launch { return "Plays on PS5 (PS4 version)" }
        return nil
    }

    /// Key art for stages and the Continue tile, falling back to the cover.
    var keyArtAsset: String? { featureAsset ?? heroAsset ?? coverAsset }
}

struct BookEntry: Codable, Hashable, Identifiable {
    enum Chapter: String, Codable, Hashable { case world, companion }
    var id: String
    var gameID: String
    var chapter: Chapter
    var section: String
    var title: String
    var body: String
    var spoiler: Bool
    var verification: String
}

struct GalleryItem: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, Hashable { case artwork, video }
    var id: String
    var gameID: String
    var kind: Kind
    var asset: String
    var title: String
    var alt: String
    var href: String?
}

struct CollectionEntry: Codable, Hashable {
    var gameID: String
    var status: OwnershipStatus
    var addedAt: Date
}

/// Everything bundled with the app. The backend replaces releases and the catalogue later.
struct Fixtures {
    var games: [CatalogGame]
    var seedCollection: [CollectionEntry]
    var releases: [Release]
    var book: [BookEntry]
    var gallery: [GalleryItem]

    static let shared: Fixtures = load()

    private struct CatalogFile: Decodable {
        var games: [CatalogGame]
        var seedCollection: [CollectionEntry]
    }

    private static func load() -> Fixtures {
        let catalog: CatalogFile = decode("catalog")
        return Fixtures(
            games: catalog.games,
            seedCollection: catalog.seedCollection,
            releases: decode("releases"),
            book: decode("book"),
            gallery: decode("gallery")
        )
    }

    static func decode<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            fatalError("Missing bundled \(name).json")
        }
        do {
            return try JSONCoding.decoder.decode(T.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Bundled \(name).json does not decode: \(error)")
        }
    }
}

enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // The feed writes fractional seconds ("2026-10-22T09:17:48.000Z"); fixtures don't.
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(s, strategy: .iso8601) { return date }
            if let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

// MARK: - PS5 catalogue search (IGDB snapshot bundled as ps5-index.json)

struct PS5Index {
    struct Entry: Decodable {
        var i: Int
        var n: String
        var d: String?
        /// The earlier PS4 release, when the game was playable on PS5 before its native release.
        var b: String?
        var v: String?
        var p: String?
        var c: String?
        var t: [String]?
    }
    private struct File: Decodable { var count: Int; var games: [Entry] }

    let entries: [Entry]
    private let folded: [String]

    static let shared = PS5Index()

    private init() {
        let file: File = Fixtures.decode("ps5-index")
        entries = file.games
        folded = file.games.map { Self.fold($0.n) }
    }

    var count: Int { entries.count }

    static func fold(_ s: String) -> String {
        let plain = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let mapped = plain.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Best matches, most relevant first: whole name, prefix, word prefix, substring; ties keep popularity order.
    func search(_ query: String, limit: Int = 30) -> [CatalogGame] {
        let q = Self.fold(query)
        guard q.count >= 2 else { return [] }
        var scored: [(Int, Int)] = []
        for (k, name) in folded.enumerated() {
            let score = name == q ? 0 : name.hasPrefix(q) ? 1 : name.contains(" " + q) ? 2 : name.contains(q) ? 3 : -1
            if score >= 0 { scored.append((score, k)) }
        }
        scored.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return scored.prefix(limit).map { game(entries[$0.1]) }
    }

    func popular(limit: Int) -> [CatalogGame] {
        entries.prefix(limit).map(game)
    }

    func game(_ e: Entry) -> CatalogGame {
        CatalogGame(
            id: "igdb-\(e.i)", name: e.n, developer: e.v, publisher: e.p, platforms: [.ps5],
            releaseDate: e.d, playableSince: e.b, igdbID: e.i, coverImageID: e.c, tones: e.t, coverage: .none
        )
    }
}
