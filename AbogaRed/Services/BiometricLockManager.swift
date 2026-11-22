import Combine
import Foundation
import LocalAuthentication

final class BiometricLockManager: ObservableObject {
    static let shared = BiometricLockManager()

    private static let enabledKey = "abogared_biometric_lock_enabled"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                isLocked = false
            }
        }
    }

    @Published var isLocked: Bool = false
    @Published var authError: String?

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.isLocked = self.isEnabled
    }

    var biometryLabel: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "Código / Biometría"
        }
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Código del dispositivo"
        }
    }

    var canUseAuthentication: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func lockIfEnabled() {
        if isEnabled {
            isLocked = true
            authError = nil
        }
    }

    func authenticate(reason: String = "Desbloquear AbogaRed para proteger tus expedientes") {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async {
                self.isLocked = false
                self.authError = nil
            }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
            DispatchQueue.main.async {
                if success {
                    self.isLocked = false
                    self.authError = nil
                } else {
                    self.authError = evalError?.localizedDescription ?? "No se pudo verificar tu identidad."
                }
            }
        }
    }

    func toggleEnabled(_ targetValue: Bool, completion: ((Bool) -> Void)? = nil) {
        if !targetValue {
            isEnabled = false
            isLocked = false
            authError = nil
            completion?(true)
            return
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = "Este dispositivo no tiene Face ID, Touch ID o código configurado."
            completion?(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Confirma tu identidad para activar el bloqueo de seguridad") { success, evalError in
            DispatchQueue.main.async {
                if success {
                    self.isEnabled = true
                    self.isLocked = false
                    self.authError = nil
                    completion?(true)
                } else {
                    self.isEnabled = false
                    self.authError = evalError?.localizedDescription
                    completion?(false)
                }
            }
        }
    }
}
