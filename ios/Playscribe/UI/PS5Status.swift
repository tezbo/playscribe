import Foundation

/// Card B: the update page's PS5 status block (docs/ps5-patch-data.md, spec "PS5 line"). It comes from the PS5 row's state
/// only. We never know what is installed on the player's console, so the version line names the update's number on PS5.
struct PS5StatusLines: Equatable {
    var primary: String
    /// Only for a live update, only when the PS5 row carries the console's own number. Never a PC number.
    var version: String?

    /// Both lines in one VoiceOver element.
    var spoken: String { [primary, version].compactMap { $0 }.joined(separator: ". ") }

    init(_ r: Release) {
        switch r.ps5State {
        case .onPS5:
            primary = "Out on PS5"
            version = r.ps5Version.flatMap { v in
                let n = v.trimmingCharacters(in: .whitespaces)
                return n.isEmpty ? nil : "This update is \(n) on PS5"
            }
        case .announced: primary = "Announced for PS5"
        case .reported: primary = "Reported on PS5"
        case .notPlanned: primary = "Not planned for PS5"
        // Not live and not announced: the page still says so in plain words (the list rows show nothing for it).
        case .pending: primary = "Not on PS5 yet"
        }
    }
}
