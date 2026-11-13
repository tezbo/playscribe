import XCTest

/// Real-simulator stills for one pose, in one test run, for `pose-stills.yml` (pick 2 of the faster screen testing research):
/// every route x text size is a fresh launch with `-qaRoute`, `-qaPose` (Book and Tabletop) and
/// `-UIPreferredContentSizeCategoryName`, and each screenshot is an attachment the workflow exports from the .xcresult.
/// No assertions beyond "the app came up": the stills are for Quinn and Iris to judge against the Mac on the same SHA.
/// Skipped unless POSE_STILLS_POSE is set (TEST_RUNNER_POSE_STILLS_POSE from xcodebuild), so normal UI test runs don't change.
///   POSE_STILLS_POSE    closed, closedLandscape, open, openPortrait, book or tabletop
///   POSE_STILLS_ROUTES  comma list of -qaRoute values (default: the shots.sh set)
///   POSE_STILLS_SIZES   comma list of std, ax3, ax5 (default std,ax5)
///   POSE_STILLS_WAIT    seconds to wait after launch before the shot (default 4; network art loads in that time)
final class PoseStillsTests: XCTestCase {
    static let categories = ["std": "UICTContentSizeCategoryL", "ax3": "UICTContentSizeCategoryAccessibilityXL",
                             "ax5": "UICTContentSizeCategoryAccessibilityXXXL"]
    static let defaultRoutes = "library,library/upcoming,add,release/dawnwalker/dawnwalker@1.1,gamepage/kcd2,settings"

    func testPoseStills() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pose = env["POSE_STILLS_POSE"], !pose.isEmpty else { throw XCTSkip("POSE_STILLS_POSE is not set") }
        func list(_ key: String, _ fallback: String) -> [String] {
            (env[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback).split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let routes = list("POSE_STILLS_ROUTES", Self.defaultRoutes)
        let sizes = list("POSE_STILLS_SIZES", "std,ax5")
        let wait = UInt32(env["POSE_STILLS_WAIT"] ?? "") ?? 4
        // Book, Open and Closed landscape are landscape; Tabletop and Open portrait are portrait (poselib.sh: rot90 vs rot0).
        let landscape = ["closedLandscape", "open", "book"].contains(pose)
        let qaPose = ["book", "tabletop"].contains(pose) ? ["-qaPose", pose] : []
        for size in sizes {
            let category = try XCTUnwrap(Self.categories[size], "unknown size \(size)")
            for route in routes {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                let app = XCUIApplication()
                app.launchArguments = ["-qaRoute", route, "-UIPreferredContentSizeCategoryName", category] + qaPose
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "\(route) \(size): the app did not come up")
                sleep(wait)
                let shot = XCUIScreen.main.screenshot()
                let attachment = XCTAttachment(screenshot: shot)
                let slug = route.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "@", with: "-")
                attachment.name = "\(slug)-\(pose)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
                print("pose still: \(attachment.name ?? "") \(Int(shot.image.size.width))x\(Int(shot.image.size.height)) pt")
                app.terminate()
            }
        }
    }
}
