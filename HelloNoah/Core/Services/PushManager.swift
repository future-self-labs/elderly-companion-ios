import Foundation
import UIKit
import UserNotifications

/// Push permission, APNs registration and taps on notifications.
///
/// Permission is asked at a sensible moment (from the caregiver dashboard, after a short
/// explanation), never at first launch. The older person's interface never asks.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Hex APNs token once registered.
    private(set) var deviceToken: String?
    /// Sends the token to the backend (`POST /me/push-tokens`). Set by the caregiver session.
    var tokenHandler: ((String) async -> Void)? {
        didSet { if let token = deviceToken { Task { await tokenHandler?(token) } } }
    }
    /// Called when the user taps a push for an alert: (alertId, elderlyId).
    var onOpenAlert: ((String, String?) -> Void)?
    /// A tapped alert that arrived before anyone listened.
    private(set) var pendingAlert: (alertId: String, elderlyId: String?)?
    /// v2.4: the older person tapped a device notice (new phone, someone wants to look along,
    /// someone now looks along): open "Wie kijkt er mee".
    var onDeviceNotice: ((String) -> Void)?
    private(set) var pendingDeviceNotice: String?

    var isAuthorized: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
        if authorization == .authorized || authorization == .provisional || authorization == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task { await tokenHandler?(token) }
    }

    func consumePendingAlert() -> (alertId: String, elderlyId: String?)? {
        defer { pendingAlert = nil }
        return pendingAlert
    }

    func consumePendingDeviceNotice() -> String? {
        defer { pendingDeviceNotice = nil }
        return pendingDeviceNotice
    }

    fileprivate func handleDeviceNotice(kind: String) {
        if let onDeviceNotice { onDeviceNotice(kind) } else { pendingDeviceNotice = kind }
    }

    fileprivate func handleTap(alertId: String, elderlyId: String?) {
        if let onOpenAlert {
            onOpenAlert(alertId, elderlyId)
        } else {
            pendingAlert = (alertId, elderlyId)
        }
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        // v2.4 device push: { "type": "device_notice", "kind": "nieuw_apparaat" | "meekijkverzoek" | "meekijker_toegevoegd" }.
        if (userInfo["type"] as? String) == "device_notice" {
            let kind = userInfo["kind"] as? String ?? ""
            await MainActor.run { self.handleDeviceNotice(kind: kind) }
            return
        }
        // Push payload for a new alert: { "type": "alert", "alertId", "elderlyId", "severity" }.
        guard (userInfo["type"] as? String) == "alert", let alertId = userInfo["alertId"] as? String else { return }
        let elderlyId = userInfo["elderlyId"] as? String
        await MainActor.run { self.handleTap(alertId: alertId, elderlyId: elderlyId) }
    }
}

/// UIKit hooks SwiftUI doesn't expose (APNs registration callbacks).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in PushManager.shared.configure() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("[Push] registration failed: %@", error.localizedDescription)
    }
}
