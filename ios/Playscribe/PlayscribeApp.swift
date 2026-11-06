import SwiftUI
import UIKit
import UserNotifications

@main
struct PlayscribeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        // Bar titles in the brand faces (Literata for large titles, Instrument Sans inline).
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: "InstrumentSans-Bold", size: 34) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
        if let inline = UIFont(name: "InstrumentSans-SemiBold", size: 17) {
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .font(PlayscribeFont.body)
                .tint(PlayscribeColor.accent)
                .foregroundStyle(PlayscribeColor.textPrimary)
                .onAppear {
                    NotificationService.shared.attach(model)
                    // Terry, 2 Nov: a cold launch starts fresh on the splash and the Library.
                    // Backgrounding keeps your place, and each game still reopens where you were
                    // reading. A notification tap opens its update after this.
                    model.startFresh()
                    model.loadCachedFeed()
                    #if INTERNAL
                    // QA: `simctl launch <device> co.codeconnectors.playscribe -qaRoute add` opens a
                    // screen without the system's "Open in" prompt that URL schemes trigger.
                    // `-qaOverlay YES` shows the debug overlay of tappable frames and reserved regions.
                    model.applyQALaunch(route: UserDefaults.standard.string(forKey: "qaRoute"),
                                        overlay: UserDefaults.standard.bool(forKey: "qaOverlay"))
                    #endif
                }
                .task {
                    await model.refreshFeed()
                    WidgetBridge.publish(model)
                    FeedClient.scheduleRefresh()
                }
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: phase) { _, p in
                    if p == .active {
                        model.tick()
                        // Quiet hours for server pushes: the relay needs the current window and zone (r050-quiet-hours-push).
                        if PushRegistrar.appCallsEnabled { PushRegistrar.syncQuietHours(model.data.quietHours) }
                        Task { await model.refreshFeed() }
                        Task { await NotificationService.shared.refreshAuthorization() }
                        NotificationService.shared.updateBadge(model.badgeCount)
                    } else if p == .background {
                        model.saveNow()
                        WidgetBridge.publish(model)
                        FeedClient.scheduleRefresh()
                    }
                }
        }
        .backgroundTask(.appRefresh(FeedClient.refreshTaskID)) {
            await model.refreshFeed()
            await FeedClient.scheduleRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be set before launch finishes so a notification tap that launched the
        // app is delivered (L-3, N-6).
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        NotificationService.shared.registerCategories()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.didRegister(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}

// precheck failure self-test: delete
let precheckSelfTest: Int = "not an int"
