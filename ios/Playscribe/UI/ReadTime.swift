import Foundation

extension Release {
    /// Whole minutes to read the notes at 220 words a minute (rounded up, at least 1); nil with no
    /// notes. PC-only lines are not counted.
    var readMinutes: Int? {
        let words = notes.flatMap(\.items).filter { !$0.isPCOnly }
            .reduce(0) { $0 + LinkedText.clean($1.text).split(whereSeparator: \.isWhitespace).count }
        return words == 0 ? nil : max(1, Int((Double(words) / 220).rounded(.up)))
    }
}
