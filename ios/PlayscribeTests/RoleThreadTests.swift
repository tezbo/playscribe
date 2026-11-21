import Foundation
import Testing
import UIKit
@testable import Playscribe

/// Mac crash on 4e3e96cd (Settings > Video lab): SwiftUI resolved a role colour on a render thread and the main-actor dynamic
/// provider trapped (EXC_BREAKPOINT in swift_task_isCurrentExecutor). Every role must resolve off the main thread.
struct RoleThreadTests {
    @Test func everyRoleResolvesOffTheMainThread() async {
        let resolved: [Int] = await Task.detached(priority: .userInitiated) {
            #expect(!Thread.isMainThread)
            var count = 0
            for spec in PlayscribeRole.all {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    _ = PlayscribeRole.uiColor(spec).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                    count += 1
                }
            }
            return [count]
        }.value
        #expect(resolved == [PlayscribeRole.all.count * 2])
    }

    /// The same on a plain GCD queue, which is what the renderer uses (no Swift task executor at all).
    @Test func rolesResolveOnABackgroundQueue() async {
        let ok: Bool = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let c = PlayscribeRole.uiColor(PlayscribeRole.bgSpec).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                cont.resume(returning: Contrast.ratio(c, UIColor(hex: 0xFBF4E6)) < 1.01)
            }
        }
        #expect(ok)
    }
}
