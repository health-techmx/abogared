import SwiftUI

struct NativeAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: WebViewModel
    @ObservedObject private var bioManager = BiometricLockManager.shared

    @State private var alerts: [MobileAlertItem] = []
    @State private var isLoading = true
    @State private var statusMessage: String?
    @State private var notificationPermission: String = "default"
    @State private var testFeedback = false

    private let burgundyPrimary = Color(red: 0.447, green: 0.184, blue: 0.216)

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Alertas de Audiencias y Términos")) {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Sincronizando agenda judicial...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if let statusMessage = statusMessage, alerts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else if alerts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sin audiencias ni vencimientos próximos")
                                .font(.subheadline.bold())
                            Text("No hay términos pendientes ni eventos para los próximos 3 días.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(alerts) { item in
                            Button(action: {
                                viewModel.load(urlString: item.url)
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.badgeText.isEmpty ? (item.isHearing ? "Audiencia" : "Término") : item.badgeText)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(badgeColor(for: item).opacity(0.16))
                                            .foregroundColor(badgeColor(for: item))
                                            .cornerRadius(6)

                                        Text(item.caseNumber)
                                            .font(.caption.bold())
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(item.fecha)
                                            .font(.caption2.bold())
                                            .foregroundColor(.secondary)
                                    }

                                    Text(item.titulo)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)

                                    HStack {
                                        if let client = item.client, !client.isEmpty {
                                            Text("Cliente: \(client)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if let hora = item.hora, !hora.isEmpty {
                                            Text(hora)
                                                .font(.caption.bold())
                                                .foregroundColor(burgundyPrimary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(header: Text("Notificaciones en este Dispositivo")) {
                    HStack {
                        Label("Notificaciones iOS", systemImage: "bell.badge.fill")
                        Spacer()
                        Text(permissionLabel)
                            .font(.caption.bold())
                            .foregroundColor(notificationPermission == "granted" ? .green : .orange)
                    }

                    if notificationPermission != "granted" {
                        Button(action: {
                            AbogaRedNotificationManager.shared.requestPermission { status in
                                notificationPermission = status
                                viewModel.pushPermissionStatusToWeb(status)
                            }
                        }) {
                            Label("Activar Notificaciones", systemImage: "checkmark.shield")
                                .foregroundColor(burgundyPrimary)
                        }
                    } else {
                        Button(action: {
                            let first = alerts.first
                            AbogaRedNotificationManager.shared.showAlertNotification(
                                alertId: "test",
                                notifyKey: nil,
                                title: first?.notifTitle ?? "⚖️ AbogaRed · Prueba de Notificación",
                                body: first?.notifBody ?? "Los avisos de audiencias y términos llegarán a tu iPhone o iPad.",
                                url: first?.url ?? "/calendario",
                                urgent: true,
                                forceShow: true
                            )
                            testFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                testFeedback = false
                            }
                        }) {
                            Label(
                                testFeedback ? "Notificación de prueba enviada ✓" : "Probar notificación ahora",
                                systemImage: "paperplane.fill"
                            )
                            .foregroundColor(burgundyPrimary)
                        }
                    }
                }

                Section(
                    header: Text("Seguridad del Despacho"),
                    footer: Text("Cuando está activo, AbogaRed solicita \(bioManager.biometryLabel) al volver a la aplicación para resguardar tus expedientes.")
                ) {
                    Toggle(isOn: Binding(
                        get: { bioManager.isEnabled },
                        set: { newValue in
                            bioManager.toggleEnabled(newValue)
                        }
                    )) {
                        Label("Bloqueo con \(bioManager.biometryLabel)", systemImage: "faceid")
                    }
                    .tint(burgundyPrimary)
                }
            }
            .navigationTitle("Alertas y Seguridad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: loadAlerts) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .refreshable {
                loadAlerts()
            }
            .onAppear {
                refreshPermission()
                loadAlerts()
            }
        }
    }

    private var permissionLabel: String {
        switch notificationPermission {
        case "granted": return "Activas"
        case "denied": return "Bloqueadas"
        default: return "Sin permiso"
        }
    }

    private func badgeColor(for item: MobileAlertItem) -> Color {
        if item.urgency == "vencido" || item.urgency == "hoy" {
            return .red
        }
        if item.urgency == "manana" {
            return .orange
        }
        return burgundyPrimary
    }

    private func refreshPermission() {
        AbogaRedNotificationManager.shared.getPermissionStatus { status in
            notificationPermission = status
        }
    }

    private func loadAlerts() {
        isLoading = true
        statusMessage = nil
        AbogaRedNotificationManager.shared.fetchAlertsForNativeUI { result in
            isLoading = false
            switch result {
            case .success(let items):
                alerts = items
                viewModel.unreadAlertsCount = items.count
            case .failure(let err):
                switch err {
                case .missingToken, .unauthorized:
                    statusMessage = "Inicia sesión para sincronizar tus alertas próximas."
                default:
                    statusMessage = "No se pudieron actualizar las alertas en este momento."
                }
            }
        }
    }
}
