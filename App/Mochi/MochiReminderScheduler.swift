import Foundation
import UserNotifications
import MyOpenScaleCore

/// Owns Mochi's pending weigh-in reminders: always replaces the whole set, so the
/// schedule can be recomputed freely. Never asks for notification permission; if it
/// isn't granted, iOS silently drops the requests.
final class MochiReminderScheduler {
    static let idPrefix = "mochi.reminder."
    static let category = "mochi.reminder"

    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current

    /// Removes every pending Mochi reminder, then schedules `reminders` (non-repeating).
    func replace(with reminders: [(PlannedReminder, title: String, body: String)]) {
        let requests = reminders.enumerated().map { index, item -> UNNotificationRequest in
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
        removeAll { [center] in
            for request in requests { center.add(request) }
        }
    }

    func cancelAll() {
        removeAll {}
    }

    private func removeAll(then next: @escaping () -> Void) {
        center.getPendingNotificationRequests { [center] pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            next()
        }
    }
}
