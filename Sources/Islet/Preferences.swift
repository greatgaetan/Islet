import Foundation
import ServiceManagement

/// The handful of things that are settings rather than data.
///
/// Task and session *data* goes to JSON (see DESIGN.md). These are process
/// facts — a launch counter, a one-time prompt flag — and `UserDefaults` is the
/// right home for them.
@MainActor
enum Preferences {
    private static let launchCountKey = "islet.launchCount"
    private static let loginItemOfferedKey = "islet.loginItemOffered"

    private static var defaults: UserDefaults { .standard }

    @discardableResult
    static func recordLaunch() -> Int {
        let count = defaults.integer(forKey: launchCountKey) + 1
        defaults.set(count, forKey: launchCountKey)
        return count
    }

    static var launchCount: Int { defaults.integer(forKey: launchCountKey) }

    /// When the evening review last ran, so it fires once a day and no more.
    static var lastRecap: Date? {
        get { defaults.object(forKey: "islet.lastRecap") as? Date }
        set { defaults.set(newValue, forKey: "islet.lastRecap") }
    }

    static var hasOfferedLoginItem: Bool {
        get { defaults.bool(forKey: loginItemOfferedKey) }
        set { defaults.set(newValue, forKey: loginItemOfferedKey) }
    }

    /// Offered at the third launch, not the first. Asking someone who has just
    /// cloned a repo to let it start with their Mac is presumptuous.
    static var shouldOfferLoginItem: Bool {
        LoginItem.isAvailable
            && !LoginItem.isEnabled
            && !hasOfferedLoginItem
            && launchCount >= 3
    }
}

@MainActor
enum LoginItem {
    /// `SMAppService` needs a real bundle, so this is inert under `swift run`.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func enable() {
        guard isAvailable else { return }
        do {
            try SMAppService.mainApp.register()
            log("registered as a login item")
        } catch {
            log("could not register login item: \(error.localizedDescription)")
        }
    }

    static func disable() {
        guard isAvailable else { return }
        do {
            try SMAppService.mainApp.unregister()
            log("unregistered as a login item")
        } catch {
            log("could not unregister login item: \(error.localizedDescription)")
        }
    }
}
