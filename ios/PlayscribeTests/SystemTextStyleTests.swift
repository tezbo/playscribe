import Foundation
import Testing

/// Light mode (Iris, 21 Nov): SwiftUI's hierarchical `.secondary` is the label colour at reduced opacity, 3.2:1 on cream.
/// Text on art-free surfaces uses the roles (textSecondary is about 6.3:1); art headers use the on-dark set.
/// Genre lists are joined with a comma, never a dot.
struct SystemTextStyleTests {
    static let banned = ["foregroundStyle(.secondary", "foregroundStyle(.tertiary", "foregroundStyle(.primary",
                         "Color.primary", "Color.secondary", "tint: .secondary", "AnyShapeStyle(.secondary"]

    @Test func appTextUsesRolesNotSystemHierarchy() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Playscribe")
        var offenders: [String] = []
        let walk = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in walk where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for b in Self.banned where line.contains(b) { offenders.append("\(url.lastPathComponent):\(i + 1) \(b)") }
            }
        }
        #expect(offenders.isEmpty, "system text styles instead of roles: \(offenders)")
    }

    @Test func genresJoinWithComma() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/GameBookParts.swift"), encoding: .utf8)
        #expect(!src.contains("genres.joined(separator: \" · \")"))
        #expect(src.contains("genres.joined(separator: \", \")"))
    }
}
