import SwiftUI
import UIKit

/// G-11, sug-terry-appearance step 2 (decided in for 0.6 on 8 Nov): Settings > Appearance, System (the default), Light or Dark.
/// The choice is stored with the rest of the player's settings and applied to every window of the app, so sheets and covers
/// follow it too. A cover or player that pins dark (the front cover, the video player) still does; the window's choice returns
/// when it closes.
nonisolated enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// What applies: `-qaAppearance light|dark|system` (internal builds, for Mac stills) wins over the setting; a distribution
    /// build ignores it, like `-qaRoute`.
    static func effective(_ stored: AppAppearance?) -> AppAppearance {
        #if INTERNAL
        if let qa = UserDefaults.standard.string(forKey: "qaAppearance"), let forced = AppAppearance(rawValue: qa) { return forced }
        #endif
        return stored ?? .system
    }

    /// Sets the style on every window of every connected scene.
    @MainActor static func apply(_ appearance: AppAppearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows { window.overrideUserInterfaceStyle = appearance.style }
        }
    }
}
