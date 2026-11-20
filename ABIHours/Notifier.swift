import Foundation
import UserNotifications

enum Notifier {
    static let category = "LUNCH"
    static let endLunchAction = "END_LUNCH"
    private static let headsUpID = "lunch.headsup"
    private static let overID = "lunch.over"

    static func registerCategories() {
        let end = UNNotificationAction(identifier: endLunchAction, title: "End lunch", options: [])
        let lunch = UNNotificationCategory(identifier: category, actions: [end], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([lunch])
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func scheduleLunch(start: Date, lengthMinutes: Int, headsUpMinutes: Int) {
        cancelLunch()
        let end = start.addingTimeInterval(TimeInterval(lengthMinutes * 60))
        if headsUpMinutes > 0 && headsUpMinutes < lengthMinutes {
            add(id: headsUpID,
                title: "\(headsUpMinutes) minutes left on lunch",
                body: "Back by \(Fmt.time(end)).",
                at: end.addingTimeInterval(TimeInterval(-headsUpMinutes * 60)))
        }
        add(id: overID,
            title: "Lunch is over",
            body: "\(lengthMinutes) minutes are up. Press the Action button when you're back.",
            at: end)
    }

    static func cancelLunch() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [headsUpID, overID])
        center.removeDeliveredNotifications(withIdentifiers: [headsUpID, overID])
    }

    private static func add(id: String, title: String, body: String, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
