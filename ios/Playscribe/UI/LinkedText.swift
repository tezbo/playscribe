import SwiftUI

/// Notes and descriptions as tappable text (Terry, 0.2.0 review): every http(s) link opens in the
/// default browser. Steam's markup is tidied first: images dropped, [dynamiclink]/[url] turned into
/// their links.
enum LinkedText {
    /// Reader performance: these ran on every body evaluation of every note row (4 regex
    /// compiles plus a new NSDataDetector each), about 1,500 compiles for Dawnwalker 1.1. Rules and
    /// the detector are built once and results are memoised by text.
    nonisolated(unsafe) private static let rules: [(NSRegularExpression, String)] = {
        let raw: [(String, String)] = [
            (#"\[img[^\]]*\]"#, ""),
            (#"\[/?(b|i|u|h\d|list|\*|p|olist|quote|code|spoiler|hr|strike)\]"#, ""),
            (#"\[dynamiclink href=\"([^\"]+)\"\]"#, "$1"),
            (#"\[url=\"?([^\]\"]+)\"?\](.*?)\[/url\]"#, "$2 $1"),
        ]
        return raw.compactMap { p, t in (try? NSRegularExpression(pattern: p)).map { ($0, t) } }
    }()
    nonisolated(unsafe) private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    nonisolated(unsafe) private static let cleanCache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>(); c.countLimit = 4000; return c
    }()
    private final class Box { let value: AttributedString; init(_ v: AttributedString) { value = v } }
    nonisolated(unsafe) private static let attributedCache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>(); c.countLimit = 2000; return c
    }()

    nonisolated static func clean(_ raw: String) -> String {
        let key = raw as NSString
        if let hit = cleanCache.object(forKey: key) { return hit as String }
        var s = raw
        for (regex, template) in rules {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
        }
        let out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanCache.setObject(out as NSString, forKey: key)
        return out
    }

    static func attributed(_ raw: String) -> AttributedString {
        let key = raw as NSString
        if let hit = attributedCache.object(forKey: key) { return hit.value }
        let text = clean(raw)
        var out = AttributedString(text)
        defer { attributedCache.setObject(Box(out), forKey: key) }
        guard let detector else { return out }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].link = url
            out[lower..<upper].foregroundColor = PlayscribeRole.action
            out[lower..<upper].underlineStyle = .single
        }
        return out
    }
}

/// Text with its links tappable; SwiftUI's Link handling opens them in the default browser.
struct LinkedTextView: View {
    var text: String
    var body: some View { Text(LinkedText.attributed(text)) }
}
