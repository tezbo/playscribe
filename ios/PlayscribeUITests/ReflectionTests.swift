import XCTest

/// R-11, Reflection mode (Terry's Duo test, 14 Nov, 0.5.5): the mirror is the live video itself, in Tabletop only. Outside Tabletop
/// there is none, and in Tabletop there is none until the video plays: no poster or snapshot stands in for it. Autoplay is off by
/// default, so the video has not started when this looks; the band where the mirror would start (under the video, or at the top
/// of the lower half in Tabletop) is the page's black beside the caption in every pose. 0.5.4 drew the poster there.
@MainActor
final class ReflectionTests: XCTestCase {
    func testNoMirrorWithoutALivePicture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "video/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let video = app.webViews.firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10), "the player's web view")
        sleep(3)
        let pose = ReleaseRowTests.pose(app)
        let window = app.windows.firstMatch.frame
        // The caption's first line ("Update 1.1 video" or the like) sits 12 pt under the band's top edge in every pose.
        let caption = app.staticTexts.allElementsBoundByIndex.filter { $0.exists && $0.frame.minY >= video.frame.maxY - 1 }
            .min { $0.frame.minY < $1.frame.minY }
        let v = video.frame
        let top = pose.contains("tabletop") ? (caption.map { $0.frame.minY - 12 } ?? v.maxY) : v.maxY
        // Right of the caption's plate (it runs 63 pt past the text) and clear of the Tabletop rail.
        let x0 = max(v.midX, (caption?.frame.maxX ?? v.minX) + 70)
        let x1 = min(v.maxX - 8, window.maxX - (pose.contains("tabletop") ? 80 : 8))
        guard x1 - x0 >= 20 else { throw XCTSkip("no clear column beside the caption [\(pose)] video \(v) caption \(caption?.frame ?? .zero)") }
        let band = CGRect(x: x0, y: top + 2, width: x1 - x0, height: 34)
        let shot = app.screenshot()
        let lum = Self.maxLuminance(in: band, of: shot.image)
        XCTAssertLessThan(lum, 0.15, "no mirror before the video plays: max luminance \(lum) in \(band) [\(pose)]")
        let att = XCTAttachment(screenshot: shot)
        att.name = "reflection-before-play [\(pose)]"; att.lifetime = .keepAlways; add(att)
    }

    /// The brightest pixel (relative luminance, 0 to 1) in `rect`, given in points, of a screenshot.
    static func maxLuminance(in rect: CGRect, of image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 1 }
        let scale = CGFloat(cg.width) / image.size.width
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard px.width > 0, px.height > 0, let crop = cg.cropping(to: px) else { return 1 }
        let w = crop.width, h = crop.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var top = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            top = max(top, (0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])) / 255)
        }
        return top
    }
}
