import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

final class WebViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var estimatedProgress: Double = 0.0
    @Published var isOffline = false
    @Published var showSplash = true
    @Published var currentPath: String = "/"
    @Published var unreadAlertsCount: Int = 0
    @Published var downloadedFile: IdentifiableURL?
    @Published var externalSafariLink: IdentifiableURL?

    weak var webView: WKWebView?

    static let homeURLString = AbogaRedNotificationManager.baseOrigin

    var isAuthenticatedRoute: Bool {
        let lower = currentPath.lowercased()
        let guestPrefixes = ["/login", "/register", "/forgot-password", "/reset-password", "/verify-email", "/confirm-password", "/auth/"]
        if lower == "/" || lower.isEmpty {
            return false
        }
        return !guestPrefixes.contains { lower.hasPrefix($0) }
    }

    func load(urlString: String) {
        let safe = AbogaRedNotificationManager.shared.sanitizeTargetUrl(urlString)
        guard let url = URL(string: safe) else { return }
        DispatchQueue.main.async {
            self.isOffline = false
            self.webView?.load(URLRequest(url: url))
        }
    }

    func reload() {
        DispatchQueue.main.async {
            self.isOffline = false
            if let webView = self.webView, webView.url != nil {
                webView.reload()
            } else {
                self.load(urlString: Self.homeURLString)
            }
        }
    }

    func pushPermissionStatusToWeb(_ status: String) {
        let clean = ["granted", "denied", "default"].contains(status) ? status : "default"
        let js = "if (typeof window.__abogaredSetIOSPermission === 'function') { window.__abogaredSetIOSPermission('\(clean)'); }"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct AbogaRedWebView: UIViewRepresentable {
    @ObservedObject var viewModel: WebViewModel
    let initialPermission: String

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = WKUserContentController()
        contentController.addUserScript(WebBridgeScript.makeUserScript(initialPermission: initialPermission))
        contentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: WebBridgeScript.handlerName
        )
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true

        let osVersion = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let shortVersion = UIDevice.current.systemVersion.split(separator: ".").prefix(2).joined(separator: ".")
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(shortVersion) Mobile/15E148 Safari/604.1 AbogaRedApp/1.2"

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor(red: 0.447, green: 0.184, blue: 0.216, alpha: 1.0)
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        context.coordinator.observeProgress(on: webView)
        viewModel.webView = webView

        if let homeURL = URL(string: WebViewModel.homeURLString) {
            webView.load(URLRequest(url: homeURL))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Estado manejado por ViewModel y NotificationCenter
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        private let viewModel: WebViewModel
        private var progressObservation: NSKeyValueObservation?
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        private static let inAppDomains: [String] = [
            "abogared.health-tech.com.mx",
            "health-tech.com.mx",
            "accounts.google.com",
            "google.com",
            "googleapis.com",
            "gstatic.com",
            "googleusercontent.com",
            "docs.google.com",
            "challenges.cloudflare.com"
        ]

        init(viewModel: WebViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            progressObservation?.invalidate()
        }

        func observeProgress(on webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.viewModel.estimatedProgress = view.estimatedProgress
                }
            }
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            viewModel.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                sender.endRefreshing()
            }
        }

        private func isAllowedInAppHost(_ host: String?) -> Bool {
            guard let host = host?.lowercased(), !host.isEmpty else { return false }
            return Self.inAppDomains.contains { domain in
                host == domain || host.hasSuffix("." + domain)
            }
        }

        private func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let keyWindow = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            var current = keyWindow?.rootViewController
            while let presented = current?.presentedViewController {
                current = presented
            }
            return current
        }

        // MARK: - JS Bridge (`window.AbogaRedIOS`)
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == WebBridgeScript.handlerName else { return }
            guard message.frameInfo.securityOrigin.host.lowercased() == "abogared.health-tech.com.mx" else { return }
            guard let payload = message.body as? [String: Any],
                  let action = payload["action"] as? String else { return }

            let data = payload["data"] as? [String: Any] ?? [:]

            switch action {
            case "requestPermission":
                AbogaRedNotificationManager.shared.requestPermission { [weak self] status in
                    self?.viewModel.pushPermissionStatusToWeb(status)
                }

            case "showNotification":
                let id = data["id"] as? String ?? ""
                let notifyKey = data["notifyKey"] as? String
                let title = data["title"] as? String ?? "AbogaRed · Alerta Legal"
                let body = data["body"] as? String ?? ""
                let url = data["url"] as? String
                let urgent = data["urgent"] as? Bool ?? false
                AbogaRedNotificationManager.shared.showAlertNotification(
                    alertId: id,
                    notifyKey: notifyKey,
                    title: title,
                    body: body,
                    url: url,
                    urgent: urgent,
                    forceShow: false
                )

            case "showTestNotification":
                let title = data["title"] as? String ?? "⚖️ AbogaRed · Prueba de Notificación"
                let body = data["body"] as? String ?? "Las alertas de audiencias, términos y citas llegarán a tu iPhone."
                let url = data["url"] as? String
                AbogaRedNotificationManager.shared.showAlertNotification(
                    alertId: "test",
                    notifyKey: nil,
                    title: title,
                    body: body,
                    url: url,
                    urgent: true,
                    forceShow: true
                )

            case "syncAlertToken":
                if let token = data["token"] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    KeychainHelper.shared.save(value: token.trimmingCharacters(in: .whitespacesAndNewlines))
                    BackgroundAlertService.shared.scheduleNextRefresh()
                    AbogaRedNotificationManager.shared.fetchAlertsForNativeUI { [weak self] result in
                        if case .success(let items) = result {
                            self?.viewModel.unreadAlertsCount = items.count
                        }
                    }
                }

            case "clearAlertToken":
                KeychainHelper.shared.delete()
                BackgroundAlertService.shared.cancelScheduledRefresh()
                DispatchQueue.main.async {
                    self.viewModel.unreadAlertsCount = 0
                }

            default:
                break
            }
        }

        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = true
                self.viewModel.isOffline = false
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let path = webView.url?.path, !path.isEmpty {
                DispatchQueue.main.async {
                    self.viewModel.currentPath = path
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let path = webView.url?.path ?? "/"
            AbogaRedNotificationManager.shared.getPermissionStatus { [weak self] status in
                self?.viewModel.pushPermissionStatusToWeb(status)
            }
            DispatchQueue.main.async {
                self.viewModel.currentPath = path.isEmpty ? "/" : path
                self.viewModel.isLoading = false
                if self.viewModel.showSplash {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.viewModel.showSplash = false
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleNavigationError(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleNavigationError(error)
        }

        private func handleNavigationError(_ error: Error) {
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                return
            }
            // Ignorar códigos de descarga convertida en WKDownload
            if nsErr.domain == "WebKitErrorDomain" && nsErr.code == 102 {
                return
            }

            let offlineCodes: Set<Int> = [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost
            ]

            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.showSplash = false
                if nsErr.domain == NSURLErrorDomain && offlineCodes.contains(nsErr.code) {
                    self.viewModel.isOffline = true
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = (url.scheme ?? "").lowercased()

            // Deep link interno tras autenticación con Google u otros flujos
            if scheme == "abogared" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let token = components?.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty {
                    let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
                    viewModel.load(urlString: "\(AbogaRedNotificationManager.baseOrigin)/auth/google/app-session?token=\(encoded)")
                } else {
                    viewModel.load(urlString: "\(AbogaRedNotificationManager.baseOrigin)/dashboard")
                }
                decisionHandler(.cancel)
                return
            }

            // Teléfono, correo o WhatsApp -> app nativa de iOS
            if ["mailto", "tel", "sms", "whatsapp"].contains(scheme) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            // Enlaces HTTP/HTTPS externos (p. ej. boletines judiciales oficiales .gob.mx) -> SFSafariViewController
            if (scheme == "http" || scheme == "https") && !isAllowedInAppHost(url.host) {
                if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                    DispatchQueue.main.async {
                        self.viewModel.externalSafariLink = IdentifiableURL(url: url)
                    }
                    decisionHandler(.cancel)
                    return
                }
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                let disposition = (httpResponse.allHeaderFields["Content-Disposition"] as? String ?? "").lowercased()
                if disposition.contains("attachment") {
                    decisionHandler(.download)
                    return
                }
            }

            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // MARK: - WKDownloadDelegate
        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AbogaRedDownloads", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let cleanName = suggestedFilename.isEmpty ? "documento_abogared.bin" : (suggestedFilename as NSString).lastPathComponent
            let destination = dir.appendingPathComponent(cleanName)
            try? FileManager.default.removeItem(at: destination)

            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let key = ObjectIdentifier(download)
            let fileURL = downloadDestinations.removeValue(forKey: key)
            if let fileURL = fileURL {
                DispatchQueue.main.async {
                    self.viewModel.downloadedFile = IdentifiableURL(url: fileURL)
                }
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        }

        // MARK: - WKUIDelegate
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if isAllowedInAppHost(url.host) {
                    webView.load(navigationAction.request)
                } else {
                    DispatchQueue.main.async {
                        self.viewModel.externalSafariLink = IdentifiableURL(url: url)
                    }
                }
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            DispatchQueue.main.async {
                guard let vc = self.topViewController() else {
                    completionHandler()
                    return
                }
                let alert = UIAlertController(title: "AbogaRed", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler() })
                vc.present(alert, animated: true)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            DispatchQueue.main.async {
                guard let vc = self.topViewController() else {
                    completionHandler(false)
                    return
                }
                let alert = UIAlertController(title: "Confirmar", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
                alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
                vc.present(alert, animated: true)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            DispatchQueue.main.async {
                guard let vc = self.topViewController() else {
                    completionHandler(nil)
                    return
                }
                let alert = UIAlertController(title: "AbogaRed", message: prompt, preferredStyle: .alert)
                alert.addTextField { tf in
                    tf.text = defaultText
                }
                alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
                alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in
                    completionHandler(alert.textFields?.first?.text)
                })
                vc.present(alert, animated: true)
            }
        }
    }
}
