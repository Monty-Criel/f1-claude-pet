import Foundation

/// When a session sits waiting for input, escalate so the user cannot miss it:
/// the menu-bar flag turns into an alert and a notification names the session.
///
/// The decision logic is pure and lives here; the side effects (icon swap,
/// notification) stay in the app delegate where the state watcher already is.
enum BoxBoxAlert {

    /// How long a session may wait before the pet starts making noise about it.
    static let threshold: TimeInterval = 120

    /// Enabled by default — the whole point is not missing a waiting session —
    /// with a menu toggle to kill it.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "boxBoxAlerts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "boxBoxAlerts") }
    }

    /// Whether to escalate right now. Fires exactly once per waiting episode:
    /// `alreadyFired` is the caller's memory of this episode, reset when the
    /// state leaves `.waiting`.
    static func shouldEscalate(waitingSince: Date?, alreadyFired: Bool,
                               enabled: Bool, now: Date = Date()) -> Bool {
        guard enabled, !alreadyFired, let since = waitingSince else { return false }
        return now.timeIntervalSince(since) >= threshold
    }
}
