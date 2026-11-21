import Testing
import Foundation

/// Tabletop stages paint the bg token, never the window's black (thread relay, 21 Nov: Updates, News and the area under
/// the player showed pure black, which would be a black half in light mode). Iris redesigns the stage content for 0.7;
/// this pins only the colour.
struct TabletopStageBgTests {
    private func source(_ name: String) throws -> String {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI").appendingPathComponent(name)
        return try String(contentsOf: ui, encoding: .utf8)
    }

    /// Each lower-half list (Updates, Search, News) sits on a full-screen bg-token background, so the standing half above
    /// the fold is the page colour in both schemes (G-4, TT-0).
    @Test(arguments: [("FeedViews.swift", "Updates"), ("FeedViews.swift", "Search"), ("NewsChapter.swift", "News")])
    func lowerHalfListsPaintTheStage(file: String, title: String) throws {
        let src = try source(file)
        let titleOverlay = try #require(src.range(of: "Text(\"\(title)\").font(PlayscribeFont.largeTitle)"), "the \(title) stage title")
        let before = src[..<titleOverlay.lowerBound]
        let pin = try #require(before.range(of: ".frame(maxHeight: .infinity, alignment: .bottom)", options: .backwards),
                               "\(title): the list is pinned to the lower half")
        let between = before[pin.upperBound...]
        #expect(between.contains(".background(PlayscribeRole.bg.ignoresSafeArea())"),
                "\(title): the Tabletop stage must paint PlayscribeRole.bg behind the upper half")
    }

    /// The Tabletop video stage's ground is the bg token; the video surface itself stays black.
    @Test func videoStageGroundIsTheBgToken() throws {
        let src = try source("PlayerView.swift")
        let stage = try #require(src.range(of: "struct TabletopVideoStage"))
        let body = src[stage.lowerBound...]
        let zstack = try #require(body.range(of: "ZStack(alignment: .topLeading) {"))
        let firstLine = body[zstack.upperBound...].split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("//") }
        #expect(firstLine == "PlayscribeRole.bg.ignoresSafeArea()")
        #expect(body.contains("VideoSurface(webView: controller.webView)\n                        .background(.black)"),
                "the video surface keeps its black")
    }
}
