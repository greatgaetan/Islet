import AppKit
import UserNotifications

/// System notifications — the *fallback*, never the main event.
///
/// The notch is the notification. This exists for the case where the built-in
/// display is unavailable (lid closed at the office) and a segment ends with
/// nowhere to show it.
@MainActor
final class Notifier {
    /// `UNUserNotificationCenter` requires a bundle identifier and traps
    /// without one, so a plain `swift run` must never touch it.
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private var hasAskedThisLaunch = false
    private var isAuthorised = false

    /// Asked when its usefulness is obvious, never at launch: a permission
    /// sheet is the worst possible first impression.
    func requestAuthorizationIfNeeded() {
        guard isAvailable, !hasAskedThisLaunch else { return }
        hasAskedThisLaunch = true

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                // This lands on UNUserNotificationCenter's own call-out queue,
                // never the main thread. `MainActor.assumeIsolated` traps here
                // — it asserts, it does not hop. Hop explicitly.
                Task { @MainActor in
                    self.isAuthorised = granted
                    if let error {
                        log("notification authorisation failed: \(error.localizedDescription)")
                    } else {
                        log("notifications \(granted ? "allowed" : "declined")")
                    }
                }
            }
    }

    func post(title: String, body: String) {
        guard isAvailable, isAuthorised else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
