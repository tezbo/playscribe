import UIKit

/// The scheme every harness still renders in: dark unless HARNESS_APPEARANCE=light (G-11).
enum HarnessAppearance {
    static var style: UIUserInterfaceStyle {
        ProcessInfo.processInfo.environment["HARNESS_APPEARANCE"] == "light" ? .light : .dark
    }
}
