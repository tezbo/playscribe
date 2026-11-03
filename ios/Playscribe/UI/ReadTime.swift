import Foundation

extension Release {
    /// Whole minutes to read the notes at 220 words a minute (rounded up, at least 1); nil with no
    /// notes. PC-only lines are not counted.
    var readMinutes: Int? {
        var hasher = Hasher()
        for item in notes.flatMap(\.items) { hasher.combine(item.text); hasher.combine(item.isPCOnly) }
        let key = "\(id):\(hasher.finalize())" as NSString
        if let hit = Self.readCache.object(forKey: key) { return hit.intValue < 0 ? nil : hit.intValue }
        let value = computeReadMinutes()
        Self.readCache.setObject(NSNumber(value: value ?? -1), forKey: key)
        return value
    }

    nonisolated(unsafe) private static let readCache = NSCache<NSString, NSNumber>()

    private func computeReadMinutes() -> Int? {
        let words = notes.flatMap(\.items).filter { !$0.isPCOnly }
            .reduce(0) { $0 + LinkedText.clean($1.text).split(whereSeparator: \.isWhitespace).count }
        return words == 0 ? nil : max(1, Int((Double(words) / 220).rounded(.up)))
    }
}
