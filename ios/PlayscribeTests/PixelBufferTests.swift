import Foundation
import Testing

/// A bitmap context must never be handed `&array`: the pointer is only valid for the init call, so the later draw writes
/// through a dangling pointer and a pixel read can come back 0. That made BrightArtScrimTests fail at random on CI (one of 15
/// patch reads was 0: row 270, left 59 against right 64, with every profile point at 64). Contexts own their buffer.
struct PixelBufferTests {
    @Test func noBitmapContextBorrowsAnArray() throws {
        let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        for dir in ["Playscribe", "PlayscribeTests", "PlayscribeUITests", "tools"] {
            guard let walk = FileManager.default.enumerator(at: ios.appendingPathComponent(dir), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk where url.pathExtension == "swift" && url.lastPathComponent != "PixelBufferTests.swift" {
                let src = try String(contentsOf: url, encoding: .utf8)
                if src.contains("CGContext(data: &") { offenders.append(url.lastPathComponent) }
            }
        }
        #expect(offenders.isEmpty, "bitmap contexts borrowing an array: \(offenders)")
    }
}
