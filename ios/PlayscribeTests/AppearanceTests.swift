import Foundation
import Testing
import UIKit
@testable import Playscribe

/// G-11, sug-terry-appearance step 2: Settings > Appearance, System by default, Light and Dark override the phone.
@MainActor @Suite(.serialized)
struct AppearanceTests {
    @Test func systemIsTheDefault() {
        let qa = UserDefaults.standard.string(forKey: "qaAppearance")
        UserDefaults.standard.removeObject(forKey: "qaAppearance")
        defer { if let qa { UserDefaults.standard.set(qa, forKey: "qaAppearance") } }
        #expect(AppAppearance.effective(nil) == .system)
        #expect(AppAppearance.effective(.light) == .light)
        #expect(AppAppearance.effective(.dark) == .dark)
        #expect(AppAppearance.system.style == .unspecified)
        #expect(AppAppearance.light.style == .light)
        #expect(AppAppearance.dark.style == .dark)
    }

    /// The Mac's launch argument still wins in internal builds, so light and dark stills need no Settings taps.
    @Test func launchArgumentOverridesTheSetting() {
        let qa = UserDefaults.standard.string(forKey: "qaAppearance")
        defer {
            if let qa { UserDefaults.standard.set(qa, forKey: "qaAppearance") } else { UserDefaults.standard.removeObject(forKey: "qaAppearance") }
        }
        UserDefaults.standard.set("light", forKey: "qaAppearance")
        #expect(AppAppearance.effective(.dark) == .light)
        UserDefaults.standard.set("dark", forKey: "qaAppearance")
        #expect(AppAppearance.effective(nil) == .dark)
    }

    /// Saved state from before the setting decodes as System; the choice survives a round trip.
    @Test func persistedChoiceRoundTrips() throws {
        var state = PersistedState(collection: [])
        #expect(state.appearance == nil)
        state.appearance = .light
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        #expect(back.appearance == .light)
    }

    /// The app is no longer locked dark by the Info.plist; the window style carries the choice.
    @Test func infoPlistNoLongerLocksDark() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") == nil)
    }
}
