import Foundation
import Testing

/// One rule for anything over art (Iris, design/taste-fixes/over-art-materials.md): a control floating over content gets
/// `floatingControl(in:)` (Liquid Glass) and a label on art gets `artLabel(in:)` (75% ink). Both live in Theme.swift, so a
/// new screen can't pick a seventh treatment. This fails on any other system material or glass call in the app's sources.
struct MaterialLintTests {
    /// Content, not over art, so the rule leaves them as they are: the chapter menu and the spoiler cover.
    static let allowed: [String: Int] = ["Chapters.swift": 1, "JournalView.swift": 1]
    static let home = "Theme.swift"

    static func sources() throws -> [URL] {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe")
        guard let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Code lines only: whole-line `//` comments are skipped, and a trailing comment is cut off.
    static func codeLines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("//") || t.hasPrefix("///") { return nil }
            if let r = line.range(of: " // ") { return String(line[..<r.lowerBound]) }
            return line
        }
    }

    static let material = try! NSRegularExpression(pattern: #"\.(ultraThin|thin|regular|thick|ultraThick|bar)Material\b|\bMaterial\.|\bUIBlurEffect\b"#)
    static let glass = try! NSRegularExpression(pattern: #"\.glassEffect\(|\.adaptiveGlass\(|\bGlassEffectContainer\b"#)

    static func count(_ re: NSRegularExpression, in line: String) -> Int {
        re.numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line))
    }

    @Test func noMaterialOutsideTheTwoRoles() throws {
        let files = try Self.sources()
        #expect(files.count > 40, "read the app sources")
        var stray: [String] = []
        for file in files where file.lastPathComponent != Self.home {
            var materials = 0
            for (i, line) in try Self.codeLines(file).enumerated() {
                let m = Self.count(Self.material, in: line)
                materials += m
                if Self.count(Self.glass, in: line) > 0 { stray.append("\(file.lastPathComponent):\(i + 1) glass outside floatingControl") }
                if m > 0, Self.allowed[file.lastPathComponent] == nil { stray.append("\(file.lastPathComponent):\(i + 1) \(line.trimmingCharacters(in: .whitespaces))") }
            }
            if let cap = Self.allowed[file.lastPathComponent], materials > cap {
                stray.append("\(file.lastPathComponent): \(materials) materials, \(cap) allowed (chapter menu / spoiler cover only)")
            }
        }
        #expect(stray.isEmpty, "Use floatingControl(in:) for a control over content or artLabel(in:) for a label on art: \(stray)")
    }

    /// Ink grounds go through artLabel too: a hand-set `ink950.opacity(x), in:` is a second value of the same role (Iris, #619:
    /// the Tabletop plates at 70% put ember text at 4.3:1 on white art).
    @Test func noHandSetInkGround() throws {
        let ink = try NSRegularExpression(pattern: #"ink950\.opacity\([0-9.]+\),\s*in:"#)
        var stray: [String] = []
        for file in try Self.sources() where file.lastPathComponent != Self.home {
            for (i, line) in try Self.codeLines(file).enumerated() where Self.count(ink, in: line) > 0 {
                stray.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        #expect(stray.isEmpty, "Use artLabel(in:) for ink behind text on art: \(stray)")
    }

    /// The allowlist stays honest: if the chapter menu or spoiler cover drops its material, its entry goes too.
    @Test func allowlistIsStillUsed() throws {
        for file in try Self.sources() where Self.allowed[file.lastPathComponent] != nil {
            let n = try Self.codeLines(file).reduce(0) { $0 + Self.count(Self.material, in: $1) }
            #expect(n == Self.allowed[file.lastPathComponent], "\(file.lastPathComponent) has \(n) materials")
        }
    }

    /// The label ink is the hero scrim's: 75% is the floor where ember on it over pure white art still reads 4.5:1.
    @Test func artLabelInkIsSeventyFivePercent() throws {
        let theme = try Self.sources().first { $0.lastPathComponent == Self.home }
        let src = try String(contentsOf: try #require(theme), encoding: .utf8)
        #expect(src.contains("static var opacity: Double { 0.75 }"))
        #expect(src.contains("func floatingControl<S: InsettableShape>(in shape: S) -> some View"))
    }
}
