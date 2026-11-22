import SafariServices
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = WebViewModel()
    @State private var initialPermission: String = "default"
    @State private var didBootstrap = false

    private let burgundyDark = Color(red: 0.290, green: 0.016, blue: 0.016) // #4A0404
    private let burgundyPrimary = Color(red: 0.447, green: 0.184, blue: 0.216) // #722F37
    private let goldAccent = Color(red: 0.831, green: 0.686, blue: 0.216) // #D4AF37

    var body: some View {
        ZStack(alignment: .top) {
            burgundyDark.ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.estimatedProgress < 1.0 && !viewModel.showSplash {
                    ProgressView(value: viewModel.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(goldAccent)
                        .frame(height: 2.5)
                        .background(burgundyDark)
                }

                AbogaRedWebView(viewModel: viewModel, initialPermission: initialPermission)
                    .ignoresSafeArea(.container, edges: .bottom)
            }

            if viewModel.isOffline {
                offlineOverlay
            }

            if viewModel.showSplash {
                splashOverlay
            }
        }
        .onAppear {
            guard !didBootstrap else { return }
            didBootstrap = true
            AbogaRedNotificationManager.shared.getPermissionStatus { status in
                initialPermission = status
                viewModel.pushPermissionStatusToWeb(status)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .abogaRedOpenURL)) { notification in
            if let urlStr = notification.object as? String {
                viewModel.load(urlString: urlStr)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .abogaRedPermissionChanged)) { notification in
            if let status = notification.object as? String {
                initialPermission = status
                viewModel.pushPermissionStatusToWeb(status)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            AbogaRedNotificationManager.shared.getPermissionStatus { status in
                initialPermission = status
                viewModel.pushPermissionStatusToWeb(status)
            }
            AbogaRedNotificationManager.shared.pollAlertsFromServer { _ in }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            BackgroundAlertService.shared.scheduleNextRefresh()
        }
        .sheet(item: $viewModel.downloadedFile) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: $viewModel.externalSafariLink) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private var splashOverlay: some View {
        ZStack {
            burgundyDark.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(goldAccent.opacity(0.6), lineWidth: 2)
                    )
                    .shadow(radius: 12)

                Text("AbogaRed")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                ProgressView()
                    .tint(goldAccent)
                    .scaleEffect(1.1)
            }
        }
        .transition(.opacity)
    }

    private var offlineOverlay: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 46))
                    .foregroundColor(burgundyPrimary)

                Text("Sin conexión a internet")
                    .font(.title3.bold())
                    .foregroundColor(.primary)

                Text("Verifica tu conexión Wi-Fi o datos móviles para sincronizar tus expedientes y alertas.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: {
                    viewModel.reload()
                }) {
                    Text("Reintentar")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(burgundyPrimary)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredBarTintColor = UIColor(red: 0.290, green: 0.016, blue: 0.016, alpha: 1.0)
        vc.preferredControlTintColor = UIColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 1.0)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
