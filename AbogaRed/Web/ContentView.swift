import SafariServices
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = WebViewModel()
    @ObservedObject private var bioManager = BiometricLockManager.shared
    @State private var initialPermission: String = "default"
    @State private var didBootstrap = false
    @State private var showAlertsSheet = false

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

                if viewModel.isAuthenticatedRoute && !viewModel.isOffline && !viewModel.showSplash {
                    nativeBottomBar
                }
            }

            if viewModel.isOffline {
                offlineOverlay
            }

            if viewModel.showSplash {
                splashOverlay
            }

            if bioManager.isLocked && !viewModel.showSplash {
                biometricLockOverlay
            }
        }
        .onAppear {
            guard !didBootstrap else { return }
            didBootstrap = true
            AbogaRedNotificationManager.shared.getPermissionStatus { status in
                initialPermission = status
                viewModel.pushPermissionStatusToWeb(status)
            }
            if bioManager.isLocked {
                bioManager.authenticate()
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
        .onReceive(NotificationCenter.default.publisher(for: .abogaRedAlertsUpdated)) { notification in
            if let count = notification.object as? Int {
                viewModel.unreadAlertsCount = count
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            AbogaRedNotificationManager.shared.getPermissionStatus { status in
                initialPermission = status
                viewModel.pushPermissionStatusToWeb(status)
            }
            AbogaRedNotificationManager.shared.pollAlertsFromServer { _ in }
            if bioManager.isLocked {
                bioManager.authenticate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            BackgroundAlertService.shared.scheduleNextRefresh()
            bioManager.lockIfEnabled()
        }
        .sheet(isPresented: $showAlertsSheet) {
            NativeAlertsView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.downloadedFile) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: $viewModel.externalSafariLink) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private var nativeBottomBar: some View {
        HStack(spacing: 4) {
            navTabButton(icon: "house.fill", title: "Panel", targetPath: "/dashboard")
            navTabButton(icon: "folder.fill", title: "Expedientes", targetPath: "/cases")
            navTabButton(icon: "calendar", title: "Calendario", targetPath: "/calendario")
            navTabButton(icon: "sparkles", title: "Wenn IA", targetPath: "/ai-assistant")

            Button(action: {
                showAlertsSheet = true
            }) {
                VStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 17, weight: .semibold))
                        if viewModel.unreadAlertsCount > 0 {
                            Text(viewModel.unreadAlertsCount > 9 ? "9+" : "\(viewModel.unreadAlertsCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 9, y: -5)
                        }
                    }
                    Text("Alertas")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(showAlertsSheet ? goldAccent : .white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(burgundyDark)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(goldAccent.opacity(0.35)),
            alignment: .top
        )
    }

    private func navTabButton(icon: String, title: String, targetPath: String) -> some View {
        let isActive = viewModel.currentPath.hasPrefix(targetPath)
        return Button(action: {
            viewModel.load(urlString: targetPath)
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: isActive ? .bold : .medium))
                Text(title)
                    .font(.system(size: 10, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isActive ? goldAccent : .white.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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

    private var biometricLockOverlay: some View {
        ZStack {
            burgundyDark.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52))
                    .foregroundColor(goldAccent)

                Text("AbogaRed Protegido")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Verifica tu identidad con \(bioManager.biometryLabel) para acceder al despacho.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                if let err = bioManager.authError, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 28)
                }

                Button(action: {
                    bioManager.authenticate()
                }) {
                    Label("Desbloquear con \(bioManager.biometryLabel)", systemImage: "faceid")
                        .font(.headline)
                        .foregroundColor(burgundyDark)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(goldAccent)
                        .cornerRadius(12)
                }
                .padding(.top, 6)
            }
        }
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
