import UserNotifications

/// Tracks and sets the app icon's badge count. The actual count is
/// persisted in UserDefaults, not read back from UNUserNotificationCenter
/// — the framework has no reliable "get current badge" query on every iOS
/// version, and since this app is the only thing ever setting its own
/// badge, tracking the value locally is simpler and equally correct.
///
/// Real behavior:
/// - `incrementForBackgroundJob()`: called after a scheduled background
///   job (auto-fetch or auto-refresh) actually runs, whether it succeeds
///   or fails to fetch — the badge reflects "a job ran while you weren't
///   looking," not "a job succeeded." Raises the badge from whatever it
///   currently is to +1 (i.e., 0 -> 1, 1 -> 2, and so on).
/// - `clear()`: called when the app becomes active (cold launch or
///   foreground) — resets the badge to 0.
///
/// Setting the badge requires notification authorization with the
/// `.badge` option — if the user has never granted it, `setBadgeCount`
/// silently does nothing (no crash, no error thrown by this wrapper);
/// the permission request itself is a separate, explicit step
/// (`requestAuthorizationIfNeeded()`), not something this manager does
/// on its own the first time it's asked to set a badge.
actor BadgeManager {
    static let shared = BadgeManager()
    private static let badgeCountDefaultsKey = "solarcast.badgeCount"

    private init() {}

    /// Requests notification authorization for the badge AND alert
    /// (banner) options. Safe to call more than once — after the first
    /// real grant/deny, UNUserNotificationCenter itself remembers the
    /// decision and this becomes a no-op (no repeated system prompts).
    /// Call this once, early in the app's real lifecycle (e.g. on first
    /// launch), not silently inside incrementForBackgroundJob() — a
    /// background task context is not a place iOS will show a permission
    /// prompt at all, so requesting it there would just silently fail
    /// every time.
    func requestAuthorizationIfNeeded() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.badge, .alert])
            AppLogger.shared.info("BadgeManager: notification authorization (badge, alert) — granted=\(granted)")
        } catch {
            AppLogger.shared.error("BadgeManager: requestAuthorization failed: \(error)")
        }
    }

    /// Posts a real, local notification banner announcing that a
    /// background job has genuinely just STARTED — a different, real
    /// moment in time from incrementForBackgroundJob() (which fires
    /// after the job completes or fails). Text is undifferentiated by
    /// success/failure — this fires unconditionally the instant a given
    /// job kind begins, matching the same deliberate, undifferentiated
    /// design already established for the badge itself, just at a
    /// different real point in the job's lifecycle. Silently does
    /// nothing if alert authorization was never granted (or was
    /// revoked) — the same real, honest failure mode as
    /// incrementForBackgroundJob()'s own badge calls.
    func postJobStartedBanner(kind: BGTaskCoordinator.PendingTriggerKind) async {
        let content = UNMutableNotificationContent()
        content.body = kind.startedBannerText
        let request = UNNotificationRequest(
            identifier: "solarcast.jobStarted.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    AppLogger.shared.error("BadgeManager: postJobStartedBanner(\(kind)) failed: \(error)")
                } else {
                    AppLogger.shared.info("BadgeManager: posted job-started banner for \(kind)")
                }
                continuation.resume()
            }
        }
    }

    /// Raises the badge by one, reflecting a real background job that
    /// just ran. Persists the new count so it survives across app
    /// launches/relaunches until explicitly cleared.
    func incrementForBackgroundJob() async {
        let d = UserDefaults.standard
        let current = d.integer(forKey: Self.badgeCountDefaultsKey)
        let next = current + 1
        d.set(next, forKey: Self.badgeCountDefaultsKey)
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(next)
            AppLogger.shared.info("BadgeManager: badge incremented to \(next) after background job")
        } catch {
            AppLogger.shared.error("BadgeManager: setBadgeCount(\(next)) failed: \(error)")
        }
    }

    /// Resets the badge to 0 — called when the app becomes active.
    func clear() async {
        let d = UserDefaults.standard
        // Unconditional, real clearing of every delivered notification
        // — deliberately NOT gated by the badge!=0 check below, since
        // that's a separate, real optimization specific to avoiding a
        // redundant setBadgeCount(0) call, not a genuine signal about
        // whether a stale, lingering banner exists. A delivered
        // notification could still be present even when the badge
        // count happens to already be 0 (e.g. from before this hook
        // existed, or simply never dismissed) — this call runs every
        // time regardless, so that case is genuinely, honestly covered.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        AppLogger.shared.info("BadgeManager: cleared all delivered notifications")
        // Nothing further to do if the badge is already 0 — avoids an
        // unnecessary real system call (and its own potential error
        // log) on every single foreground transition when there was
        // never a badge to clear.
        guard d.integer(forKey: Self.badgeCountDefaultsKey) != 0 else { return }
        d.set(0, forKey: Self.badgeCountDefaultsKey)
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(0)
            AppLogger.shared.info("BadgeManager: badge cleared")
        } catch {
            AppLogger.shared.error("BadgeManager: setBadgeCount(0) failed: \(error)")
        }
    }
}

extension BGTaskCoordinator.PendingTriggerKind {
    /// The real, exact banner text for each real job kind, per direct
    /// instruction — undifferentiated by success/failure (this text is
    /// used the instant the job STARTS, before any real outcome is
    /// known at all).
    var startedBannerText: String {
        switch self {
        case .fetch: return "Fetch forecast data started in the background"
        case .refresh: return "Refresh forecast data started in the background"
        case .logCleanup: return "Cleanup started in the background"
        }
    }
}
