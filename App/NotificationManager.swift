import Foundation
import UserNotifications

/// Local notifications for weigh-ins captured while the app is backgrounded:
/// a "saved" confirmation, and an actionable "Was this you?" with Confirm /
/// Not me buttons answerable straight from the notification.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    /// Routed to the app model (set by AppModel).
    var onConfirm: ((UUID) -> Void)?
    var onReject: ((UUID) -> Void)?

    private let reviewCategory = "weighin.review"
    private let confirmAction = "weighin.confirm"
    private let rejectAction = "weighin.reject"
    private let readingIDKey = "readingID"

    /// Set the delegate + action category early (so notification taps that launch
    /// the app are handled). Safe to call before authorization.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let confirm = UNNotificationAction(identifier: confirmAction, title: String(localized: "This was me"),
                                           options: [.authenticationRequired])
        let reject = UNNotificationAction(identifier: rejectAction, title: String(localized: "Not me"),
                                          options: [.destructive])
        let category = UNNotificationCategory(identifier: reviewCategory,
                                              actions: [confirm, reject],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifySaved(weightKg: Double) {
        notifySaved(title: String(localized: "Weigh-in saved"),
                    body: String(localized: "\(weightKg.formatted(.number.precision(.fractionLength(1)))) kg saved to Apple Health."))
    }

    /// A "saved" confirmation with custom wording (e.g. in Mochi's voice).
    func notifySaved(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        post(content)
    }

    func notifyNeedsReview(readingID: UUID, weightKg: Double) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Was this you?")
        content.body = String(localized: "A \(weightKg.formatted(.number.precision(.fractionLength(1)))) kg weigh-in needs confirming.")
        content.categoryIdentifier = reviewCategory
        content.userInfo = [readingIDKey: readingID.uuidString]
        content.sound = .default
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// In the foreground the dashboard/overlay already shows this, so suppress the
    /// banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }

    /// Confirm / Not me tapped on the notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard
            let idString = response.notification.request.content.userInfo[readingIDKey] as? String,
            let id = UUID(uuidString: idString)
        else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            if action == confirmAction { onConfirm?(id) }
            else if action == rejectAction { onReject?(id) }
            // default (tapped body) just opens the app; the dashboard card handles it.
        }
    }
}
