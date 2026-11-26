import XCTest

/// Terry on beta 3 (build 18, real Duo, 22 Nov): the marks under the hero cards are not one amber bar; "a kind of sliding
/// transition between amber | marks". Mac stills are taken at rest, so they always showed one bar. The page edge lit each
/// current leaf amber at once and slid one amber capsule over it in 0.2 s, so during and just after a swipe two amber shapes
/// showed: the new lit leaves and the capsule still on its way.
///
/// Measured in motion: screenshots back to back through each flick and its settle, counting separate amber runs along the
/// marks row. One bar means one run in every frame.
@MainActor
final class HeroMarksTests: XCTestCase {
    func testMarksStayOneAmberBarThroughSwipes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "fill-library/12"]
        app.launch()
        sleep(4)
        if ReleaseRowTests.pose(app).contains("pose: tabletop") { app.terminate(); throw XCTSkip("Tabletop's deck is the stage, no pager") }
        let pager = app.descendants(matching: .any)["latestDeckPager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5), "the deck is on screen")
        // The page indicator (Iris, beta 4): one element over the dots row; the band is its middle 20 pt.
        let indicator = app.descendants(matching: .any)["deckIndicator"]
        let cardCount = indicator.waitForExistence(timeout: 5) ? Int(indicator.label.split(separator: " ").last ?? "") ?? 0 : 0
        guard cardCount > 2 else { app.terminate(); throw XCTSkip("needs three or more cards and the indicator (\(cardCount))") }
        let f = indicator.frame
        let row = CGRect(x: f.minX, y: f.midY - 10, width: f.width, height: 20)

        // The measurement must see the marks before it can say anything about them (Mac at 85ab7f8e: 0 runs in every frame of
        // every pose, so neither red nor green meant anything). A system alert over the app is dismissed; a screenshot that
        // comes back black (the Mac simulator's inner display in Open) skips, and the motion is measured from a recording.
        Self.dismissSystemAlerts()
        let first = XCUIScreen.main.screenshot()
        let firstImage = first.image
        if Self.isBlack(firstImage) {
            app.terminate()
            throw XCTSkip("the screenshot is black (Open inner display on the Mac simulator): measure from a recording")
        }
        let atRest = Self.amberRuns(in: row, of: firstImage)
        if atRest != 1 {
            let a = XCTAttachment(screenshot: first)
            a.name = "marks-not-seen-at-rest"
            a.lifetime = .keepAlways
            add(a)
            XCTFail("measurement invalid: \(atRest) amber runs at rest in \(row) (brightest band pixel \(Self.reddest(in: row, of: firstImage))), so the motion count would mean nothing")
            return
        }

        var worst = 0, samples = 0
        var log: [String] = []
        let flicks = 12
        for flick in 0..<flicks {
            let forward = flick % 6 < 4
            let from = pager.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.8 : 0.2, dy: 0.3))
            let to = pager.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.2 : 0.8, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
            let start = Date()
            var runs: [Int] = []
            while Date().timeIntervalSince(start) < 1.0 {
                let shot = XCUIScreen.main.screenshot()
                let n = Self.amberRuns(in: row, of: shot.image)
                runs.append(n)
                samples += 1
                if n > 1 && worst <= 1 {
                    let a = XCTAttachment(screenshot: shot)
                    a.name = "two-amber-runs-flick\(flick)"
                    a.lifetime = .keepAlways
                    add(a)
                }
                worst = max(worst, n)
            }
            log.append("flick \(flick): runs per frame \(runs)")
        }
        let note = "\(ReleaseRowTests.pose(app)); \(samples) frames; most amber runs in one frame \(worst)\n" + log.joined(separator: "\n")
        print("HeroMarks: \(note)")
        XCTContext.runActivity(named: note) { _ in }
        XCTAssertGreaterThan(samples, 6, "the burst sampled the motion")
        XCTAssertLessThanOrEqual(worst, 1, "the marks showed \(worst) separate amber shapes in one frame")
        let rest = Self.amberRuns(in: row, of: XCUIScreen.main.screenshot().image)
        XCTAssertEqual(rest, 1, "at rest the marks are one amber bar")
    }

    /// Taps the first button of any SpringBoard alert (notification permission and the like) so it cannot dim the screen.
    static func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { return }
            let allow = alert.buttons["Allow"]
            (allow.exists ? allow : alert.buttons.element(boundBy: 0)).tap()
            sleep(1)
        }
    }

    /// Whether every sampled pixel of the screenshot is near black.
    static func isBlack(_ image: UIImage) -> Bool {
        let size = image.size
        return reddest(in: CGRect(origin: .zero, size: size), of: image, step: 8).max <= 12
    }

    /// The pixel with the largest red-minus-blue in `rect` (points), and the brightest channel seen, for the failure message.
    static func reddest(in rect: CGRect, of image: UIImage, step: Int = 1) -> (rgb: [Int], max: Int) {
        guard case let (bytes, w, h)? = pixels(in: rect, of: image) else { return ([], 0) }
        var best = [0, 0, 0], bestScore = Int.min, top = 0
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                let i = (y * w + x) * 4
                let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                top = max(top, r, g, b)
                if r - b > bestScore { bestScore = r - b; best = [r, g, b] }
            }
        }
        return (best, top)
    }

    static func pixels(in rect: CGRect, of image: UIImage) -> ([UInt8], Int, Int)? {
        guard let cg = image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / image.size.width
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard px.width > 0, px.height > 0, let crop = cg.cropping(to: px) else { return nil }
        let w = crop.width, h = crop.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4)), w, h)
    }

    /// Separate amber runs along the row's middle band, `rect` in points. Amber is the accent (255, 176, 79); a run ends at a
    /// gap wider than 2 pt.
    static func amberRuns(in rect: CGRect, of image: UIImage) -> Int {
        guard case let (bytes, w, h)? = pixels(in: rect, of: image), let cg = image.cgImage else { return 0 }
        let scale = CGFloat(cg.width) / image.size.width
        func amber(_ x: Int) -> Bool {
            for y in 0..<h {
                let i = (y * w + x) * 4
                let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                if r > 215 && g > 130 && g < 210 && b < 130 && r - b > 110 { return true }
            }
            return false
        }
        let gap = Int((2 * scale).rounded())
        var runs = 0, sinceAmber = Int.max
        for x in 0..<w {
            if amber(x) {
                if sinceAmber > gap { runs += 1 }
                sinceAmber = 0
            } else if sinceAmber != Int.max {
                sinceAmber += 1
            }
        }
        return runs
    }
}
