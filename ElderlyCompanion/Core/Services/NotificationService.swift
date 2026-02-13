import UserNotifications
import Foundation

@Observable
final class NotificationService {
    private(set) var isAuthorized: Bool = false

    init() {
        Task {
            await checkAuthorization()
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                isAuthorized = granted
            }
            return granted
        } catch {
            return false
        }
    }

    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    /// Schedule a local notification for a medication reminder
    func scheduleMedicationReminder(_ medication: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "Medication Reminder"
        content.body = "Time to take your \(medication.name)"
        content.sound = .default
        content.categoryIdentifier = "MEDICATION_REMINDER"

        let components = Calendar.current.dateComponents([.hour, .minute], from: medication.time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: "medication-\(medication.id)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Schedule a daily check-in notification
    func scheduleDailyCheckIn(at time: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Daily Check-In"
        content.body = "Good morning! How are you feeling today?"
        content.sound = .default
        content.categoryIdentifier = "DAILY_CHECKIN"

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: "daily-checkin",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Remove all scheduled notifications
    func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
