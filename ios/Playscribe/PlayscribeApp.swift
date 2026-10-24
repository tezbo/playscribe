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
        if let large = UIFont(name: "Literata72pt-SemiBold", size: 34) {
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
                    model.loadCachedFeed()
                    #if INTERNAL
                    // QA: `simctl launch <device> co.codeconnectors.playscribe -qaRoute add` opens a
                    // screen without the system's "Open in" prompt that URL schemes trigger.
                    if let route = UserDefaults.standard.string(forKey: "qaRoute"), let url = URL(string: "playscribe://\(route)") {
                        model.handle(url: url)
                    }
                    #endif
                }
                .task {
                    await model.refreshFeed()
                    FeedClient.scheduleRefresh()
                }
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: phase) { _, p in
                    if p == .active {
                        model.tick()
                        Task { await model.refreshFeed() }
                        Task { await NotificationService.shared.refreshAuthorization() }
                        NotificationService.shared.updateBadge(model.badgeCount)
                    } else if p == .background {
                        model.saveNow()
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
