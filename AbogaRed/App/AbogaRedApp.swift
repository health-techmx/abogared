import SwiftUI

@main
struct AbogaRedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleIncomingDeepLink(url)
                }
        }
    }

    private func handleIncomingDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "abogared" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let token = components?.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty {
            let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            let sessionUrl = "\(AbogaRedNotificationManager.baseOrigin)/auth/google/app-session?token=\(encoded)"
            NotificationCenter.default.post(name: .abogaRedOpenURL, object: sessionUrl)
        } else {
            let dashUrl = "\(AbogaRedNotificationManager.baseOrigin)/dashboard"
            NotificationCenter.default.post(name: .abogaRedOpenURL, object: dashUrl)
        }
    }
}
