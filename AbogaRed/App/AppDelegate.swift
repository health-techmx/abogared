import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = AbogaRedNotificationManager.shared
        BackgroundAlertService.shared.register()
        BackgroundAlertService.shared.scheduleNextRefresh()

        requestNotificationPermissionOnFirstLaunch()
        return true
    }

    private func requestNotificationPermissionOnFirstLaunch() {
        let key = "abogared_asked_ios_notifications"
        if UserDefaults.standard.bool(forKey: key) {
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        AbogaRedNotificationManager.shared.getPermissionStatus { status in
            if status == "default" {
                AbogaRedNotificationManager.shared.requestPermission { _ in }
            }
        }
    }
}
