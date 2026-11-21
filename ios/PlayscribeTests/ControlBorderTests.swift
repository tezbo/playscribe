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
            let r = ImageRenderer(content: view)
            r.scale = 1
            return try #require(r.cgImage)
        }
        func pixel(_ cg: CGImage, _ x: Int, _ y: Int) throws -> UIColor {
            var rgba = [UInt8](repeating: 0, count: 4)
            let ctx = try #require(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return UIColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255, blue: CGFloat(rgba[2]) / 255, alpha: 1)
        }
        // The field spans x 20...180, y 20...64; its top edge's border row is y 20, mid-width.
        let light = try render(.light, border: true)
        let edge = try pixel(light, 100, 20), ground = try pixel(light, 100, 5)
        #expect(Contrast.ratio(edge, ground) >= 3, "light border \(Contrast.ratio(edge, ground)):1 on bg")
        let dark = try render(.dark, border: true), plain = try render(.dark, border: false)
        for (x, y) in [(100, 20), (20, 42), (179, 42), (100, 63)] {
            #expect(Contrast.ratio(try pixel(dark, x, y), try pixel(plain, x, y)) < 1.01, "dark unchanged at \(x),\(y)")
        }
    }
}
