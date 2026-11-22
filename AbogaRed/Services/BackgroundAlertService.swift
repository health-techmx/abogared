import BackgroundTasks
import Foundation

final class BackgroundAlertService {
    static let shared = BackgroundAlertService()
    static let taskIdentifier = "com.abogared.app.alertRefresh"

    private var registered = false

    private init() {}

    func register() {
        guard !registered else { return }
        registered = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleAppRefresh(task: refreshTask)
        }
    }

    func scheduleNextRefresh() {
        guard let token = KeychainHelper.shared.read(), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func cancelScheduledRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let lock = NSLock()
        var finished = false
        let finishOnce: (Bool) -> Void = { success in
            lock.lock()
            let alreadyFinished = finished
            finished = true
            lock.unlock()
            if !alreadyFinished {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = {
            finishOnce(false)
        }

        AbogaRedNotificationManager.shared.pollAlertsFromServer { success in
            finishOnce(success)
        }
    }
}
