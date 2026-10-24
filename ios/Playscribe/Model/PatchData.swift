import Foundation

// The patch data contract shared with the backend. See docs/ps5-patch-data.md.
// Field names and cases follow that spec exactly; the few app-only fields are optional
// so records from the backend decode without them.

enum Platform: String, Codable, CaseIterable, Hashable {
    case ps5, xboxSeries, switch2, pc

    var label: String {
        switch self {
        case .ps5: "PS5"
        case .xboxSeries: "Xbox Series X|S"
        case .switch2: "Nintendo Switch 2"
        case .pc: "PC"
        }
    }
}

enum ReleaseKind: String, Codable, Hashable {
    case dayOne, hotfix, patch, major, silent

    var label: String {
        switch self {
        case .dayOne: "Day-one patch"
        case .hotfix: "Hotfix"
        case .patch: "Patch"
        case .major: "Major update"
        case .silent: "Silent update"
        }
    }

    /// "Major only" notifications cover major updates and day-one patches (N-3).
    var countsAsMajor: Bool { self == .major || self == .dayOne }
}

enum KindBasis: String, Codable, Hashable { case studio, inferred }

enum Trust: String, Codable, Hashable { case official, secondary }

enum Verification: String, Codable, Hashable, Comparable {
    /// A person confirmed it against an official post that names this platform.
    case official
    /// Press only.
    case reported
    /// Extracted automatically, not confirmed yet. Never shown.
    case pending

    private var rank: Int { switch self { case .pending: 0; case .reported: 1; case .official: 2 } }
    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

enum PlatformStatus: String, Codable, Hashable { case live, announced, notPlanned, unknown }

struct Field<T: Codable & Hashable>: Codable, Hashable {
    var value: T
    var verification: Verification
    var sourceID: String
    var checkedAt: Date

    enum CodingKeys: String, CodingKey { case value, verification, sourceID = "sourceId", checkedAt }
}

struct NoteItem: Codable, Hashable {
    init(text: String, platforms: [Platform]? = nil, ps5ProOnly: Bool = false, spoiler: Bool? = nil) {
        self.text = text; self.platforms = platforms; self.ps5ProOnly = ps5ProOnly; self.spoiler = spoiler
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        platforms = try c.decodeIfPresent([Platform].self, forKey: .platforms)
        ps5ProOnly = try c.decodeIfPresent(Bool.self, forKey: .ps5ProOnly) ?? false
        spoiler = try c.decodeIfPresent(Bool.self, forKey: .spoiler)
    }

    var text: String
    /// nil means every platform.
    var platforms: [Platform]?
    var ps5ProOnly: Bool
    /// App extension: story content that is hidden until revealed.
    var spoiler: Bool?
}

struct NoteSection: Codable, Hashable {
    var title: String
    var items: [NoteItem]
}

struct PlatformRelease: Codable, Hashable {
    init(platform: Platform, status: PlatformStatus, version: Field<String>? = nil, sizeBytes: Field<Int64>? = nil,
         liveAt: Field<Date>? = nil, bundles: [String] = [], verification: Verification) {
        self.platform = platform; self.status = status; self.version = version; self.sizeBytes = sizeBytes
        self.liveAt = liveAt; self.bundles = bundles; self.verification = verification
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform = try c.decode(Platform.self, forKey: .platform)
        status = try c.decode(PlatformStatus.self, forKey: .status)
        version = try c.decodeIfPresent(Field<String>.self, forKey: .version)
        sizeBytes = try c.decodeIfPresent(Field<Int64>.self, forKey: .sizeBytes)
        liveAt = try c.decodeIfPresent(Field<Date>.self, forKey: .liveAt)
        bundles = try c.decodeIfPresent([String].self, forKey: .bundles) ?? []
        verification = try c.decode(Verification.self, forKey: .verification)
    }

    var platform: Platform
    var status: PlatformStatus
    /// As the platform shows it, for example "01.004.000".
    var version: Field<String>?
    var sizeBytes: Field<Int64>?
    var liveAt: Field<Date>?
    /// Ids of PC-side releases folded into this console patch.
    var bundles: [String]
    /// Overall verification of this platform row.
    var verification: Verification
}

/// One update as the studio announces it (for example "Update 1.1").
struct Release: Codable, Hashable, Identifiable {
    var id: String
    var gameID: String
    var displayName: String
    var kind: ReleaseKind
    var kindBasis: KindBasis
    var announcedAt: Date
    var notes: [NoteSection]
    var sourceIDs: [String]
    var platforms: [PlatformRelease]

    // App extensions: Playscribe's editorial layer and media.
    var headline: String?
    var summary: String?
    var keyChanges: [String]?
    var video: ReleaseVideo?
    var videoNote: String?
    /// The short line a notification carries after "is live on PS5:" (N-4).
    var pushLine: String?
    /// Set on releases created by the internal "Simulate update" tool.
    var simulated: Bool?
    /// A simulated release stays hidden until its notification is due.
    var arrivesAt: Date?

    // JSON keys follow docs/api.md (camelCase "Id").
    enum CodingKeys: String, CodingKey {
        case id, gameID = "gameId", displayName, kind, kindBasis, announcedAt, notes, sourceIDs = "sourceIds", platforms
        case headline, summary, keyChanges, video, videoNote, pushLine, simulated, arrivesAt
    }

    init(id: String, gameID: String, displayName: String, kind: ReleaseKind, kindBasis: KindBasis, announcedAt: Date,
         notes: [NoteSection], sourceIDs: [String], platforms: [PlatformRelease], headline: String? = nil, summary: String? = nil,
         keyChanges: [String]? = nil, video: ReleaseVideo? = nil, videoNote: String? = nil, pushLine: String? = nil, simulated: Bool? = nil, arrivesAt: Date? = nil) {
        self.id = id; self.gameID = gameID; self.displayName = displayName; self.kind = kind; self.kindBasis = kindBasis
        self.announcedAt = announcedAt; self.notes = notes; self.sourceIDs = sourceIDs; self.platforms = platforms
        self.headline = headline; self.summary = summary; self.keyChanges = keyChanges; self.video = video
        self.videoNote = videoNote; self.pushLine = pushLine; self.simulated = simulated; self.arrivesAt = arrivesAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        gameID = try c.decode(String.self, forKey: .gameID)
        displayName = try c.decode(String.self, forKey: .displayName)
        kind = try c.decode(ReleaseKind.self, forKey: .kind)
        kindBasis = try c.decodeIfPresent(KindBasis.self, forKey: .kindBasis) ?? .inferred
        announcedAt = try c.decode(Date.self, forKey: .announcedAt)
        notes = try c.decodeIfPresent([NoteSection].self, forKey: .notes) ?? []
        sourceIDs = try c.decodeIfPresent([String].self, forKey: .sourceIDs) ?? []
        platforms = try c.decodeIfPresent([PlatformRelease].self, forKey: .platforms) ?? []
        headline = try c.decodeIfPresent(String.self, forKey: .headline)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        keyChanges = try c.decodeIfPresent([String].self, forKey: .keyChanges)
        video = try c.decodeIfPresent(ReleaseVideo.self, forKey: .video)
        videoNote = try c.decodeIfPresent(String.self, forKey: .videoNote)
        pushLine = try c.decodeIfPresent(String.self, forKey: .pushLine)
        simulated = try c.decodeIfPresent(Bool.self, forKey: .simulated)
        arrivesAt = try c.decodeIfPresent(Date.self, forKey: .arrivesAt)
    }

    /// Combines a feed record with Playscribe's curated record for the same release: the feed's
    /// platform rows win where present, curated rows fill the gaps, and editorial fields are kept.
    func merged(withFeed feed: Release) -> Release {
        var out = feed
        var rows = feed.platforms
        for row in platforms where !rows.contains(where: { $0.platform == row.platform }) { rows.append(row) }
        out.platforms = rows
        if !notes.isEmpty { out.notes = notes }
        out.headline = feed.headline ?? headline
        out.summary = feed.summary ?? summary
        out.keyChanges = feed.keyChanges ?? keyChanges
        out.video = feed.video ?? video
        out.videoNote = feed.videoNote ?? videoNote
        out.pushLine = feed.pushLine ?? pushLine
        return out
    }
}

struct ReleaseVideo: Codable, Hashable {
    var youtubeID: String
    var label: String
    var duration: String?
    var posted: String
    var posterAsset: String?

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(youtubeID)")! }
}

// MARK: - PS5 state (docs/ux-acceptance.md, "PS5 verification states")

enum PS5State: Hashable {
    /// live + official: unread, badge, push.
    case onPS5
    /// official announcement for PS5.
    case announced
    /// press only. A silent update is reported with no notes.
    case reported
    /// not shown anywhere.
    case pending
    /// No PS5 row, or one that is announced/unknown without an official PS5 announcement.
    case pcOnly
    /// An official post says it is not coming to PS5.
    case notPlanned
}

extension Release {
    var ps5: PlatformRelease? { platforms.first { $0.platform == .ps5 } }

    var ps5State: PS5State {
        guard let p = ps5 else { return .pcOnly }
        if p.verification == .pending { return .pending }
        switch p.status {
        case .live: return p.verification == .official ? .onPS5 : .reported
        case .announced: return p.verification == .official ? .announced : .pcOnly
        case .notPlanned: return p.verification == .official ? .notPlanned : .pcOnly
        case .unknown: return .pcOnly
        }
    }

    /// Shown in the main journal (above the "PC only so far" group).
    var isPS5Listed: Bool { [.onPS5, .announced, .reported].contains(ps5State) }

    /// The date this release went live on PS5, or was announced.
    var ps5Date: Date { ps5?.liveAt?.value ?? announcedAt }

    /// The newest date on any platform, for sorting PC-only releases.
    var latestDate: Date { platforms.compactMap { $0.liveAt?.value }.max() ?? announcedAt }

    var ps5Version: String? { ps5?.version?.value }

    var isSilent: Bool { kind == .silent || (ps5State == .reported && notes.isEmpty && (keyChanges ?? []).isEmpty && headline == nil) }

    var noteCount: Int { notes.reduce(0) { $0 + $1.items.count } }
}
