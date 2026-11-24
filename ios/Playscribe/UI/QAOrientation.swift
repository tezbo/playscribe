import UIKit

#if INTERNAL
/// QA (internal builds only): `-qaOrientation landscape` or `-qaOrientation portrait` asks every window scene for that
/// interface orientation at launch. The result is written to the `qaOrientationResult` user default (ok, or the error),
/// so a UI test that sees no turn can say why.
enum QAOrientation {
    static var requested: UIInterfaceOrientationMask? {
        guard BuildChannel.showsInternalTools else { return nil }
        switch UserDefaults.standard.string(forKey: "qaOrientation") {
        case "landscape": return .landscapeLeft
        case "portrait": return .portrait
        default: return nil
        }
    }

    @MainActor static func apply(_ mask: UIInterfaceOrientationMask) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                NSLog("qaOrientation: \(error)")
                UserDefaults.standard.set("\(error)", forKey: "qaOrientationResult")
            }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
#endif
