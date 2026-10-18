import Foundation
import UserNotifications
import MyOpenScaleCore

/// Owns Mochi's pending weigh-in reminders: always replaces the whole set, so the
/// schedule can be recomputed freely. Never asks for notification permission; if it
/// isn't granted, iOS silently drops the requests.
final class MochiReminderScheduler {
    static let idPrefix = "mochi.reminder."
    static let category = "mochi.reminder"
    /// Upper bound for the number of reminders ever scheduled at once (iOS keeps 64 pending per app).
    static let maxCount = 64

    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current

    /// Removes every pending Mochi reminder, then schedules `reminders` (non-repeating).
    func replace(with reminders: [(PlannedReminder, title: String, body: String)]) {
        let requests = reminders.prefix(Self.maxCount).enumerated().map { index, item -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = Self.category
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.0.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            // Index-based ids: a racing second replace overwrites rather than duplicates.
            return UNNotificationRequest(identifier: Self.idPrefix + String(index), content: content, trigger: trigger)
        }
        removeAll()
        for request in requests { center.add(request) }
    }

    /// Removes every Mochi reminder, pending and already delivered.
    func cancelAll() {
        removeAll()
    }

    /// Synchronous removal of the fixed id set (index-based ids never exceed `maxCount`):
    /// no async snapshot, so a cancel can never miss requests a concurrent replace adds.
    private func removeAll() {
        let ids = (0..<Self.maxCount).map { Self.idPrefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
