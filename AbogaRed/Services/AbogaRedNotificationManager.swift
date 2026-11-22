import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let abogaRedOpenURL = Notification.Name("abogaRedOpenURL")
    static let abogaRedPermissionChanged = Notification.Name("abogaRedPermissionChanged")
    static let abogaRedAlertsUpdated = Notification.Name("abogaRedAlertsUpdated")
}

struct MobileAlertItem: Identifiable {
    let id: String
    let notifyKey: String
    let notifTitle: String
    let notifBody: String
    let titulo: String
    let caseNumber: String
    let client: String?
    let fecha: String
    let hora: String?
    let badgeText: String
    let urgency: String
    let diffDays: Int
    let urgent: Bool
    let isHearing: Bool
    let url: String
}

enum AlertsFetchError: Error {
    case missingToken
    case invalidEndpoint
    case unauthorized
    case networkFailed
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

    func fetchAlertsForNativeUI(completion: @escaping (Result<[MobileAlertItem], AlertsFetchError>) -> Void) {
        guard let token = KeychainHelper.shared.read()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(.missingToken))
            }
            return
        }

        guard let endpointURL = URL(string: Self.defaultAlertsEndpoint) else {
            DispatchQueue.main.async {
                completion(.failure(.invalidEndpoint))
            }
            return
        }

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(token, forHTTPHeaderField: "X-AbogaRed-Alert-Token")
        req.setValue("AbogaRedApp/1.2 (iOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            if error != nil {
                DispatchQueue.main.async {
                    completion(.failure(.networkFailed))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(.networkFailed))
                }
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                KeychainHelper.shared.delete()
                DispatchQueue.main.async {
                    completion(.failure(.unauthorized))
                }
                return
            }
            guard (200...299).contains(http.statusCode), let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(.networkFailed))
                }
                return
            }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawAlerts = root["alerts"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .abogaRedAlertsUpdated, object: 0)
                    completion(.success([]))
                }
                return
            }

            let items: [MobileAlertItem] = rawAlerts.enumerated().map { idx, item in
                let id = (item["id"] as? String) ?? "\(idx)"
                let diffDays = (item["diff_days"] as? NSNumber)?.intValue ?? 99
                let fechaIso = (item["fecha_iso"] as? String) ?? ""
                let notifyKey = (item["notify_key"] as? String) ?? "\(id):\(fechaIso)"
                let notifTitle = (item["notif_title"] as? String) ?? "AbogaRed · Alerta Legal"
                let titulo = (item["titulo"] as? String) ?? "Diligencia próxima"
                let notifBody = (item["notif_body"] as? String) ?? titulo
                let caseNumber = (item["case_number"] as? String) ?? "Expediente"
                let client = item["client"] as? String
                let fecha = (item["fecha"] as? String) ?? fechaIso
                let hora = item["hora"] as? String
                let badgeText = (item["badge_text"] as? String) ?? ""
                let urgency = (item["urgency"] as? String) ?? ""
                let urgent = (item["urgent"] as? Bool) ?? (diffDays <= 1)
                let isHearing = (item["is_hearing"] as? Bool) ?? false
                let target = self?.sanitizeTargetUrl(item["url"] as? String) ?? (Self.baseOrigin + "/calendario")

                return MobileAlertItem(
                    id: id,
                    notifyKey: notifyKey,
                    notifTitle: notifTitle,
                    notifBody: notifBody,
                    titulo: titulo,
                    caseNumber: caseNumber,
                    client: client,
                    fecha: fecha,
                    hora: hora,
                    badgeText: badgeText,
                    urgency: urgency,
                    diffDays: diffDays,
                    urgent: urgent,
                    isHearing: isHearing,
                    url: target
                )
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .abogaRedAlertsUpdated, object: items.count)
                completion(.success(items))
            }
        }.resume()
    }

    func pollAlertsFromServer(completion: @escaping (Bool) -> Void) {
        fetchAlertsForNativeUI { [weak self] result in
            guard let self = self else {
                completion(false)
                return
            }
            switch result {
            case .failure(let err):
                completion(err == .missingToken || err == .unauthorized)
            case .success(let items):
                self.getPermissionStatus { status in
                    guard status == "granted" else {
                        completion(true)
                        return
                    }
                    var shown = 0
                    for item in items where item.diffDays <= 3 {
                        if shown >= 5 { break }
                        if self.showAlertNotification(
                            alertId: item.id,
                            notifyKey: item.notifyKey,
                            title: item.notifTitle,
                            body: item.notifBody,
                            url: item.url,
                            urgent: item.urgent,
                            forceShow: false
                        ) {
                            shown += 1
                        }
                    }
                    completion(true)
                }
            }
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
