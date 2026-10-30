import Foundation
import UserNotifications

/// Posts native macOS notifications (Notification Center, top-right corner).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let category = "BREAK"
    private static let snoozeAction = "SNOOZE"
    private static let doneAction = "DONE"

    private(set) var status: UNAuthorizationStatus = .notDetermined
    var isAuthorized: Bool { status == .authorized || status == .provisional }

    /// UNUserNotificationCenter crashes when the binary isn't inside an app bundle.
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done")
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [done, snooze],
                                   intentIdentifiers: [], options: [])
        ])
        refreshStatus()
    }

    func refreshStatus(_ completion: (() -> Void)? = nil) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.status = settings.authorizationStatus
                completion?()
            }
        }
    }

    func requestAuthorization(_ completion: (() -> Void)? = nil) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            self.refreshStatus(completion)
        }
    }

    func post(_ r: Reminder, tip: Exercise?) {
        let content = UNMutableNotificationContent()
        content.title = r.name
        var body = r.message
        if let tip { body += body.isEmpty ? "\(tip.title): \(tip.detail)" : "\n\(tip.title): \(tip.detail)" }
        content.body = body
        content.categoryIdentifier = Self.category
        content.userInfo = ["id": r.id.uuidString]
        // The chime is played by the app itself so the user's chosen sound (or silence) is respected.
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == Self.snoozeAction,
           let idString = response.notification.request.content.userInfo["id"] as? String,
           let id = UUID(uuidString: idString) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ReminderStore.shared.snooze(id) }
            }
        }
        completionHandler()
    }
}
