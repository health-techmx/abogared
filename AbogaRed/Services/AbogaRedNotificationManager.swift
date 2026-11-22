import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let abogaRedOpenURL = Notification.Name("abogaRedOpenURL")
    static let abogaRedPermissionChanged = Notification.Name("abogaRedPermissionChanged")
}

final class AbogaRedNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AbogaRedNotificationManager()

    static let baseOrigin = "https://abogared.health-tech.com.mx"
    static let defaultAlertsEndpoint = "https://abogared.health-tech.com.mx/api/mobile/alerts"
    private static let notifiedKeysDefaultsKey = "abogared_notified_keys_json"
    private static let sevenDaysSeconds: TimeInterval = 7 * 24 * 60 * 60

    private let prefsLock = NSLock()

    private override init() {
        super.init()
    }

    func sanitizeTargetUrl(_ rawUrl: String?) -> String {
        guard let rawUrl = rawUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUrl.isEmpty, rawUrl != "#" else {
            return Self.baseOrigin + "/calendario"
        }
        if rawUrl.hasPrefix("/"), !rawUrl.hasPrefix("//") {
            return Self.baseOrigin + rawUrl
        }
        if rawUrl == Self.baseOrigin || rawUrl.hasPrefix(Self.baseOrigin + "/") {
            return rawUrl
        }
        return Self.baseOrigin + "/calendario"
    }

    func getPermissionStatus(completion: @escaping (String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                status = "granted"
            case .denied:
                status = "denied"
            case .notDetermined:
                status = "default"
            @unknown default:
                status = "default"
            }
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    func requestPermission(completion: @escaping (String) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
                DispatchQueue.main.async {
                    if let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    } else if let fallbackURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(fallbackURL)
                    }
                    completion("denied")
                }
                return
            }

            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                let finalStatus = granted ? "granted" : "denied"
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .abogaRedPermissionChanged, object: finalStatus)
                    if granted {
                        BackgroundAlertService.shared.scheduleNextRefresh()
                    }
                    completion(finalStatus)
                }
            }
        }
    }

    private func wasKeyNotified(_ notifyKey: String) -> Bool {
        prefsLock.lock()
        defer { prefsLock.unlock() }

        guard let raw = UserDefaults.standard.string(forKey: Self.notifiedKeysDefaultsKey),
              let data = raw.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: TimeInterval] else {
            return false
        }

        guard let ts = dict[notifyKey] else { return false }
        return (Date().timeIntervalSince1970 - ts) < Self.sevenDaysSeconds
    }

    private func markKeyNotified(_ notifyKey: String) {
        prefsLock.lock()
        defer { prefsLock.unlock() }

        let now = Date().timeIntervalSince1970
        let cutoff = now - Self.sevenDaysSeconds
        var cleaned: [String: TimeInterval] = [:]

        if let raw = UserDefaults.standard.string(forKey: Self.notifiedKeysDefaultsKey),
           let data = raw.data(using: .utf8),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: TimeInterval] {
            for (k, ts) in existing where ts >= cutoff {
                cleaned[k] = ts
            }
        }

        cleaned[notifyKey] = now
        if let serialized = try? JSONSerialization.data(withJSONObject: cleaned),
           let jsonString = String(data: serialized, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: Self.notifiedKeysDefaultsKey)
        }
    }

    @discardableResult
    func showAlertNotification(
        alertId: String,
        notifyKey: String?,
        title: String,
        body: String,
        url: String?,
        urgent: Bool,
        forceShow: Bool = false
    ) -> Bool {
        if !forceShow, let key = notifyKey, !key.isEmpty, wasKeyNotified(key) {
            return false
        }

        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "AbogaRed · Alerta Legal"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBody = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Tienes una diligencia o plazo próximo en tu agenda."
            : body.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeUrl = sanitizeTargetUrl(url)

        let content = UNMutableNotificationContent()
        content.title = safeTitle
        content.body = safeBody
        content.sound = .default
        content.threadIdentifier = "com.abogared.alerts"
        content.interruptionLevel = .active
        content.userInfo = [
            "url": safeUrl,
            "urgent": urgent
        ]

        let cleanId = alertId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestIdentifier: String
        if forceShow {
            requestIdentifier = "abogared-test-\(Int(Date().timeIntervalSince1970 * 1000))"
        } else {
            let suffix = cleanId.isEmpty ? UUID().uuidString : cleanId
            requestIdentifier = "abogared-\(suffix)"
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.4, repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }

        if !forceShow, let key = notifyKey, !key.isEmpty {
            markKeyNotified(key)
        }

        return true
    }

    func pollAlertsFromServer(completion: @escaping (Bool) -> Void) {
        guard let token = KeychainHelper.shared.read(), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(true)
            return
        }

        getPermissionStatus { [weak self] status in
            guard let self = self, status == "granted" else {
                completion(true)
                return
            }

            guard let endpointURL = URL(string: Self.defaultAlertsEndpoint) else {
                completion(false)
                return
            }

            var req = URLRequest(url: endpointURL)
            req.httpMethod = "GET"
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(token.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-AbogaRed-Alert-Token")
            req.setValue("AbogaRedApp/1.2 (iOS)", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: req) { data, response, error in
                if error != nil {
                    completion(false)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(false)
                    return
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    KeychainHelper.shared.delete()
                    completion(true)
                    return
                }
                guard (200...299).contains(http.statusCode), let data = data else {
                    completion(false)
                    return
                }

                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let alerts = root["alerts"] as? [[String: Any]] else {
                    completion(true)
                    return
                }

                var shown = 0
                for (idx, item) in alerts.enumerated() {
                    if shown >= 5 { break }
                    let diffDays = (item["diff_days"] as? NSNumber)?.intValue ?? 99
                    if diffDays > 3 { continue }

                    let id = (item["id"] as? String) ?? "\(idx)"
                    let fechaIso = (item["fecha_iso"] as? String) ?? ""
                    let notifyKey = (item["notify_key"] as? String) ?? "\(id):\(fechaIso)"
                    let title = (item["notif_title"] as? String) ?? "AbogaRed · Alerta Legal"
                    let body = (item["notif_body"] as? String) ?? (item["titulo"] as? String) ?? "Diligencia próxima"
                    let url = item["url"] as? String
                    let urgent = (item["urgent"] as? Bool) ?? (diffDays <= 1)

                    if self.showAlertNotification(
                        alertId: id,
                        notifyKey: notifyKey,
                        title: title,
                        body: body,
                        url: url,
                        urgent: urgent,
                        forceShow: false
                    ) {
                        shown += 1
                    }
                }

                completion(true)
            }.resume()
        }
    }

    // Mostrar banner, sonido e ícono aunque la app esté abierta en primer plano (estilo WhatsApp)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Navegar al expediente o calendario exacto al tocar la notificación
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawUrl = response.notification.request.content.userInfo["url"] as? String
        let safeUrl = sanitizeTargetUrl(rawUrl)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .abogaRedOpenURL, object: safeUrl)
        }
        completionHandler()
    }
}
