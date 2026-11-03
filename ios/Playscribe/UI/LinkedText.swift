import SwiftUI

/// Notes and descriptions as tappable text (Terry, 0.2.0 review): every http(s) link opens in the
/// default browser. Steam's markup is tidied first: images dropped, [dynamiclink]/[url] turned into
/// their links.
enum LinkedText {
    nonisolated static func clean(_ raw: String) -> String {
        var s = raw
        let rules: [(String, String)] = [
            (#"\[img[^\]]*\]"#, ""),
            (#"\[/?(b|i|u|h\d|list|\*|p|olist|quote|code|spoiler|hr|strike)\]"#, ""),
            (#"\[dynamiclink href=\"([^\"]+)\"\]"#, "$1"),
            (#"\[url=\"?([^\]\"]+)\"?\](.*?)\[/url\]"#, "$2 $1"),
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func attributed(_ raw: String) -> AttributedString {
        let text = clean(raw)
        var out = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].link = url
            out[lower..<upper].foregroundColor = PlayscribeColor.accent
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
