import Foundation

/// Card B: the update page's PS5 status block (docs/ps5-patch-data.md, spec "PS5 line"). It comes from the PS5 row's state
/// only. We never know what is installed on the player's console, so the version line names the update's number on PS5.
struct PS5StatusLines: Equatable {
    var primary: String
    /// Only for a live update, only when the PS5 row carries the console's own number. Never a PC number.
    var version: String?

    /// Both lines in one VoiceOver element.
    /// The backend's source id for a build number read from the PS5 build list (backend/src/store.ts).
    static let buildListSource = "ps5-builds"

    var spoken: String { [primary, version].compactMap { $0 }.joined(separator: ". ").replacingOccurrences(of: "\u{2060}", with: "") }

    init(_ r: Release) {
        switch r.ps5State {
        case .onPS5:
            primary = "Out on PS5"
            // A build number the backend read from the PS5 build list (source ps5-builds) is reported, not official: it says so
            // (Iris on #617). VoiceOver reads the same words.
            let reported = Self.isReportedBuild(r)
            version = r.ps5Version.flatMap { v in
                let n = v.trimmingCharacters(in: .whitespaces)
                // A word joiner after each dot: a version number never breaks at its dots (Redesign rule). Stripped for VoiceOver.
                let shown = n.replacingOccurrences(of: ".", with: ".\u{2060}")
                return n.isEmpty ? nil : reported ? "Reported as \(shown) on PS5" : "This update is \(shown) on PS5"
            }
        case .announced: primary = "Announced for PS5"
        case .reported: primary = r.isPS4PlayingOnPS5 ? Release.ps4PlaysOnPS5 : "Reported on PS5"
        case .notPlanned: primary = "Not planned for PS5"
        // Not live and not announced: the page still says so in plain words (the list rows show nothing for it).
        case .pending: primary = "Not on PS5 yet"
        }
    }

    /// True when the PS5 number came from the PS5 build list (reported, not official).
    static func isReportedBuild(_ r: Release) -> Bool { r.ps5?.version?.sourceID == buildListSource }

    /// The short PS5 number for a chip or a one-line status: the bare number when official, "Reported as <n>" when it came from
    /// the build list (Iris on #619: the Tabletop plate and the cover chip match the update page line). VoiceOver reads the same
    /// words. Nil without a PS5 number; never a PC number.
    static func buildChip(_ r: Release) -> String? {
        guard let n = r.ps5Version?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        return isReportedBuild(r) ? "Reported as \(n)" : n
    }
}
