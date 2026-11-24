import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// s-06-control-border (Iris, design/tokens-0.6-light-values.md): fields, search fields and outlined buttons draw the control
/// border, 3:1 or better in light on the surfaces they sit on; dark is unchanged.
@MainActor
struct ControlBorderTests {
    /// Every text field, our own search fields, Tabletop's search button and every bordered (outlined) button in the app source
    /// carries `.controlBorder(` within 40 lines (the field's container closes within that). A new control without it fails here.
    @Test func everyControlDrawsTheBorder() throws {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI")
        let files = try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 20, "read the UI sources")
        let markers = ["TextField(", ".buttonStyle(.bordered)", "struct TabletopSearchButton"]
        var found: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                guard markers.contains(where: code.contains) else { continue }
                let site = "\(file.lastPathComponent):\(i + 1)"
                found.append(site)
                let window = lines[i..<min(lines.count, i + 40)].joined(separator: "\n")
                #expect(window.contains(".controlBorder("), "\(site) has no control border: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        // The control styles this story covers (a list, so a removed site is noticed too).
        let files_ = Set(found.map { String($0.split(separator: ":")[0]) })
        for f in ["LibraryView.swift", "AddGameSheet.swift", "FeedViews.swift", "GameBookParts.swift", "Chapters.swift",
                  "JournalView.swift", "KeepCurrentCard.swift", "SayItView.swift", "TabletopSearch.swift"] {
            #expect(files_.contains(f), "\(f) has a control")
        }
        #expect(ControlKind.allCases.count == 5)
    }

    @Test func lightBorderMeetsThreeToOne() {
        let border = PlayscribeRole.resolved(PlayscribeRole.controlBorderSpec, light: true)
        for surface in [PlayscribeRole.bgSpec, PlayscribeRole.cardSpec, PlayscribeRole.surfaceSpec] {
            let r = Contrast.ratio(border, PlayscribeRole.resolved(surface, light: true))
            #expect(r >= 3, "\(surface.name): \(r)")
        }
    }

    @Test func darkBorderIsClearUnlessKept() {
        var a: CGFloat = 1
        PlayscribeRole.resolved(PlayscribeRole.controlBorderSpec, light: false).getRed(nil, green: nil, blue: nil, alpha: &a)
        #expect(a == 0)
        // The default every field uses: clear in dark, not black (1c086d4 drew opaque black here).
        var b: CGFloat = 1
        UIColor(PlayscribeRole.controlBorder(keepingDark: .clear))
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getRed(nil, green: nil, blue: nil, alpha: &b)
        #expect(b == 0, "the default control border is clear in dark")
        let kept = UIColor(PlayscribeRole.controlBorder(keepingDark: PlayscribeColor.vellum500))
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(Contrast.ratio(kept, UIColor(PlayscribeColor.vellum500)) == 1)
    }

    /// Pixels: a field on bg in light shows the border at 3:1 or better; in dark the same field is pixel-identical to one without it.
    @Test func renderedBorder() throws {
        func alpha(_ cg: CGImage, _ x: Int, _ y: Int) throws -> UInt8 {
            let ctx = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return ctx.data!.assumingMemoryBound(to: UInt8.self)[3]
        }
        func render(_ scheme: ColorScheme, border: Bool) throws -> CGImage {
            let field = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let view = ZStack {
                PlayscribeRole.bg
                Group {
                    if border {
                        Color.clear.frame(width: 160, height: 44)
                            .background(PlayscribeRole.chipFill, in: field)
                            .controlBorder(.searchField, in: field)
                    } else {
                        Color.clear.frame(width: 160, height: 44).background(PlayscribeRole.chipFill, in: field)
                    }
                }
            }
            .frame(width: 200, height: 84)
            .environment(\.colorScheme, scheme)
            // bug-065, named by #608's pixels (CI f4fcc368: edge, ground and field all #000000 at 200x84, beside seven "image
            // provider timed out while waiting for phase 6" lines and a 15 s run): under load the renderer can time out and hand
            // back a fully transparent image. The view's ground is opaque, so a transparent corner can only be that timeout; render
            // again (at most three times) rather than read colours from an image that never drew. The 3:1 check is unchanged.
            for _ in 0..<3 {
                let r = ImageRenderer(content: view)
                r.scale = 1
                let cg = try #require(r.cgImage)
                if try alpha(cg, 5, 5) > 0 { return cg }
            }
            struct BlankRender: Error, CustomStringConvertible {
                var description: String { "ImageRenderer returned a blank (transparent) image three times; no colours to check" }
            }
            throw BlankRender()
        }
        func pixel(_ cg: CGImage, _ x: Int, _ y: Int) throws -> UIColor {
            let ctx = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // The context owns its buffer: `&array` is only valid for the init call, so a later draw wrote through a dangling
            // pointer and a read could come back 0 (BrightArtScrimTests on CI: one sample of 15 read 0, row 270 left 59 right 64).
            ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            let rgba = Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: 4))
            return UIColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255, blue: CGFloat(rgba[2]) / 255, alpha: 1)
        }
        // The field spans x 20...180, y 20...64; its top edge's border row is y 20, mid-width.
        let light = try render(.light, border: true)
        let edge = try pixel(light, 100, 20), ground = try pixel(light, 100, 5)
        // bug-065: the failure is intermittent on CI and never reproduced in 50 isolated and 5 full-suite loops, so the message
        // carries the pixels and the image, to name the cause the next time it fails (the threshold is unchanged).
        func hex(_ c: UIColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        }
        let centre = try pixel(light, 100, 42)
        #expect(Contrast.ratio(edge, ground) >= 3,
                "light border \(Contrast.ratio(edge, ground)):1 on bg: edge \(hex(edge)) ground \(hex(ground)) field \(hex(centre)), image \(light.width)x\(light.height), want edge #857A68")
        let dark = try render(.dark, border: true), plain = try render(.dark, border: false)
        for (x, y) in [(100, 20), (20, 42), (179, 42), (100, 63)] {
            let d = try pixel(dark, x, y), p = try pixel(plain, x, y)
            #expect(Contrast.ratio(d, p) < 1.01, "dark unchanged at \(x),\(y): bordered \(hex(d)) plain \(hex(p)), images \(dark.width)x\(dark.height) and \(plain.width)x\(plain.height)")
        }
    }

    /// Iris on #557 (Mac b2400b3b: white cards on the sheet grey at 1.12:1 under Reduce Transparency): every sheet's Form and
    /// List wraps its sections in `CardSections`, which outlines each card in the control border in that mode.
    @Test func sheetsOutlineTheirCards() throws {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI")
        for (file, lists) in [("SettingsView.swift", 1), ("AddGameSheet.swift", 2), ("AddMethods.swift", 2)] {
            let src = try String(contentsOf: ui.appendingPathComponent(file), encoding: .utf8)
            // `CardSections {` or `CardSections(rowFill: …) {` (Settings sets its own light cards, Iris beta 4).
            let wrapped = src.components(separatedBy: "CardSections {").count - 1 + src.components(separatedBy: "CardSections(").count - 1
            #expect(wrapped == lists, "\(file): \(wrapped) of \(lists) lists outline their cards")
        }
    }

    /// Iris on #557: the card outline under Reduce Transparency is the control border in light and #6F6A7C in dark, 3:1 or
    /// better on the dark sheet it bounds (#1C1C1E, luminance 0.012, and black), with luminance at least 0.14.
    @Test func cardEdgeShowsInBothSchemes() {
        let light = PlayscribeRole.resolved(PlayscribeRole.cardEdgeSpec, light: true)
        #expect(Contrast.ratio(light, PlayscribeRole.resolved(PlayscribeRole.controlBorderSpec, light: true)) < 1.01)
        let dark = PlayscribeRole.resolved(PlayscribeRole.cardEdgeSpec, light: false)
        #expect(Contrast.luminance(dark) >= 0.14, "dark card edge luminance \(Contrast.luminance(dark))")
        for ground in [UIColor(hex: 0x1C1C1E), UIColor(hex: 0x000000)] {
            #expect(Contrast.ratio(dark, ground) >= 3, "dark card edge \(Contrast.ratio(dark, ground)):1")
        }
        let src = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Playscribe/UI/CardSections.swift"), encoding: .utf8)) ?? ""
        #expect(src.contains(".stroke(PlayscribeRole.cardEdge,"), "the card style strokes the card edge role")
    }

    /// The outline slices: the first row carries the card's top edge, the last its bottom, and a middle row only its sides
    /// (its path runs past the row so the clip removes the top and bottom).
    @Test func cardRowEdges() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 44)
        let only = CardRowEdge(top: true, bottom: true, radius: CardRowBackground.radius).path(in: rect).boundingRect
        #expect(rect.contains(only), "a one-row card's outline sits inside the row")
        let middle = CardRowEdge(top: false, bottom: false, radius: CardRowBackground.radius).path(in: rect).boundingRect
        #expect(middle.minY < 0 && middle.maxY > rect.maxY, "a middle row draws no top or bottom edge")
        let firstRow = CardRowEdge(top: true, bottom: false, radius: CardRowBackground.radius).path(in: rect).boundingRect
        #expect(firstRow.minY >= 0 && firstRow.maxY > rect.maxY, "the first row draws the top edge only")
    }
}
