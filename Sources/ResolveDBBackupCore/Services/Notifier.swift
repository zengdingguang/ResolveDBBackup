import Foundation
import UserNotifications
import AppKit

/// macOS 通知（备份失败/成功）。
/// v1.7.6：修复通知不弹出——①权限未决定时先请求；②设置 delegate 让前台也弹窗。
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        // App 在前台时也弹窗 + 播声音
        completionHandler([.banner, .sound])
    }
}

enum Notifier {
    private static let delegate = NotifierDelegate()
    private static var delegateConfigured = false

    /// 无 app bundle 的进程（如裸二进制跑 CLI）调用 UNUserNotificationCenter 会崩溃，
    /// 因此 bundleIdentifier 为空时跳过通知。
    private static var bundleAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// 配置 delegate（让前台通知也弹窗），只需配置一次。
    private static func configureDelegateIfNeeded() {
        guard !delegateConfigured, bundleAvailable else { return }
        UNUserNotificationCenter.current().delegate = delegate
        delegateConfigured = true
    }

    static func requestAuthorization() async {
        guard bundleAvailable else { return }
        configureDelegateIfNeeded()
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func notify(title: String, body: String, sound: Bool = true) async {
        guard bundleAvailable else { return }
        configureDelegateIfNeeded()
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        // 权限未决定时先请求一次（用户可能之前忽略了授权弹窗）
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
