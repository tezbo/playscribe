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
    /// Extracted automatically, not confirmed yet.
    case pending
    /// A Steam patch with no word on PS5, taken as out on PS5 too (Steam rule, 27 Oct).
    case assumed

    /// Unknown values from a newer feed decode as pending rather than failing the whole feed.
    init(from decoder: Decoder) throws {
        self = Verification(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .pending
    }

    private var rank: Int { switch self { case .pending: 0; case .reported: 1; case .assumed: 2; case .official: 3 } }
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
        alert = try c.decodeIfPresent(Alert.self, forKey: .alert)
    }

    /// Which one alert this row earns (docs/api.md): `standard` when live and official, `quiet`
    /// (tag "Unconfirmed") when the press reports it live.
    struct Alert: Codable, Hashable {
        var style: String
        var tag: String?
        var isQuiet: Bool { style == "quiet" }
    }
    var alert: Alert?

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
    /// Where the notes came from (Terry, 27 Oct): the Steam post and the studio's PS5 page.
    struct Links: Codable, Hashable { var steamNotes: URL?; var ps5Page: URL? }
    var links: Links?
    /// Set on releases created by the internal "Simulate update" tool.
    var simulated: Bool?
    /// A simulated release stays hidden until its notification is due.
    var arrivesAt: Date?

    // JSON keys follow docs/api.md (camelCase "Id").
    enum CodingKeys: String, CodingKey {
        case id, gameID = "gameId", displayName, kind, kindBasis, announcedAt, notes, sourceIDs = "sourceIds", platforms
        case headline, summary, keyChanges, video, videoNote, pushLine, links, simulated, arrivesAt
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
        links = try c.decodeIfPresent(Links.self, forKey: .links)
        simulated = try c.decodeIfPresent(Bool.self, forKey: .simulated)
        arrivesAt = try c.decodeIfPresent(Date.self, forKey: .arrivesAt)
    }

    /// Combines a feed record with Playscribe's curated record for the same release: the feed's
    /// platform rows win where present, curated rows fill the gaps, and editorial fields are kept.
    func merged(withFeed feed: Release) -> Release {
        var out = feed
        var rows = feed.platforms
        for row in platforms {
            if let i = rows.firstIndex(where: { $0.platform == row.platform }) {
                // V-4: an official curated row is never downgraded by a press-reported feed row.
                if row.verification == .official && rows[i].verification != .official { rows[i] = row }
            } else {
                rows.append(row)
            }
        }
        out.platforms = rows
        if !notes.isEmpty { out.notes = notes }
        out.headline = feed.headline ?? headline
        out.summary = feed.summary ?? summary
        out.keyChanges = feed.keyChanges ?? keyChanges
        out.video = feed.video ?? video
        out.videoNote = feed.videoNote ?? videoNote
        out.pushLine = feed.pushLine ?? pushLine
        out.links = feed.links ?? links
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

// MARK: - PS5-only content (GR-2)

enum PCOnly {
    /// Terms that mark a line as PC-only: PC hardware, upscalers and frame generation, mouse and
    /// keyboard, Steam and Steam Deck, GPU vendors. Such lines never lead a PS5 page or a push.
    static let pattern = try! Regex(#"(?i)\b(frame ?gen\w*|dlss|fsr|xess|amd|radeon|nvidia|geforce|rtx|intel arc|steam( deck)?|mouse|keyboard|ultrawide|vram|directx|dx1[12]|vulkan)\b"#)

    static func matches(_ text: String) -> Bool { text.contains(pattern) }
}

extension NoteItem {
    /// Applies only to PC: tagged so, or naming PC-only hardware or features.
    var isPCOnly: Bool {
        if let p = platforms, !p.contains(.ps5) { return true }
        return PCOnly.matches(text)
    }
}

extension Release {
    /// Key changes fit for a PS5 page: PC-only lines removed.
    var ps5KeyChanges: [String] { (keyChanges ?? []).filter { !PCOnly.matches($0) } }

    /// The headline for a PS5 page; a PC-only headline gives way to the top PS5 key change.
    var ps5Headline: String? {
        if let h = headline, !PCOnly.matches(h) { return h }
        return ps5KeyChanges.first ?? (headline == nil ? nil : displayName)
    }

    var ps5Summary: String? { summary.flatMap { PCOnly.matches($0) ? nil : $0 } }
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
        // Terry, 26 Oct: Steam is the source of truth. A release live on Steam counts as released
        // on PS5 unless we can confirm otherwise.
        let liveElsewhere = platforms.contains { $0.platform != .ps5 && $0.status == .live }
        guard let p = ps5 else { return liveElsewhere ? .onPS5 : .pcOnly }
        // Released (docs/ps5-patch-data.md): live and official, assumed, pending, or reported on
        // a release Steam or the studio has.
        if p.verification == .pending && p.status != .live { return .pending }
        switch p.status {
        // V-4 stays rare: Unconfirmed only when the press reports it and neither Steam nor the
        // studio has it.
        case .live:
            let hasSource = links?.steamNotes != nil || links?.ps5Page != nil
            return p.verification != .reported || liveElsewhere || hasSource ? .onPS5 : .reported
        case .announced: return p.verification == .official ? .announced : .pcOnly
        case .notPlanned: return p.verification == .official ? .notPlanned : .pcOnly
        case .unknown: return .pcOnly
        }
    }

    /// V-4: Reported (including silent) releases are shown to people as Unconfirmed.
    var isUnconfirmed: Bool { ps5State == .reported }

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
