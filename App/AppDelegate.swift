import UIKit
import BackgroundTasks
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var bgTaskCoordinator: BGTaskCoordinator?
    private static let hasLaunchedBeforeKey = "solarcast.hasLaunchedBefore"

    // BGTaskScheduler.register(forTaskWithIdentifier:) MUST complete before
    // application(_:didFinishLaunchingWithOptions:) returns — but the safe,
    // documented place for it is willFinishLaunchingWithOptions, which
    // Apple guarantees runs strictly before didFinishLaunchingWithOptions.
    // Registering inside didFinishLaunchingWithOptions itself (as this was
    // previously written) is a well-documented source of BGTaskScheduler
    // silently never firing tasks — no crash, no error, no log line,
    // exactly the symptom reported. Moving registration here, before
    // anything else in the launch sequence runs.
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Genuinely first-ever launch on this install — cancel any stale
        // pending BGTaskScheduler requests before anything else runs.
        // BGTaskScheduler state is OS-level and persists independently of
        // this app's own UserDefaults, so a request submitted under an
        // EARLIER version of this app's scheduling logic could otherwise
        // sit in the OS queue indefinitely. cancelAllTaskRequests() is a
        // real, documented API that clears every pending request for this
        // app's bundle specifically (the OS itself scopes it — no
        // per-identifier enumeration needed, and no way for this call to
        // affect any other app's tasks). Placed BEFORE registerTasks() and
        // any scheduling below, so a legitimate same-launch submission is
        // never wiped out afterward.
        if UserDefaults.standard.object(forKey: Self.hasLaunchedBeforeKey) == nil {
            BGTaskScheduler.shared.cancelAllTaskRequests()
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)
            AppLogger.shared.info("AppDelegate: first launch on this install — cancelled all pending BGTaskScheduler requests")
        }
        Task {
            await BadgeManager.shared.requestAuthorizationIfNeeded()
        }
        let coordinator = DIContainer.shared.makeBGTaskCoordinator()
        coordinator.registerTasks()
        self.bgTaskCoordinator = coordinator
        return true
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Segmented control tint is set by ThemeStore.applyOnLaunch(), called
        // from SolarCastApp's onAppear — not here. ThemeStore is the single
        // place theme resolution happens; duplicating that logic in
        // AppDelegate (which runs before ThemeStore even exists) would mean
        // two independent implementations that could silently drift apart.
        guard bgTaskCoordinator != nil else { return true }
        Task {
            let result = await DIContainer.shared.performAppLaunchFetchIfNeeded()
            switch result {
            case .fetchedSuccessfully:
                // AppDelegate has no view model reference — this is how the
                // dashboard (once DashboardView exists and is observing)
                // finds out a launch-time fetch wrote new data. Without
                // this, the same "fetched, but nothing reloads" gap that
                // affected the resume path also existed here: whichever of
                // this Task or DashboardView.task's own loadAll() finished
                // first left stale data on screen with nothing to catch up.
                await MainActor.run {
                    NotificationCenter.default.post(name: .forecastDataRefreshed, object: nil)
                }
            case .fetchFailed(let error):
                // Previously this case was indistinguishable from
                // .notStale (both silently did nothing) — worse, the
                // underlying bug meant a real failure was reported as
                // .fetchedSuccessfully, triggering the notification (and
                // the "Data Refreshed" alert in DashboardView) even though
                // nothing was actually refreshed. Now a genuine failure is
                // logged here and does NOT post the refreshed notification.
                // AppDelegate has no UI capability to show an alert
                // directly — the failure is still visible via the log.
                AppLogger.shared.error("AppDelegate: launch-time staleness fetch failed: \(error.humanReadableMessage)")
            case .quotaExhausted:
                // Genuinely not a real failure — expected, ordinary, and
                // will resolve itself at the next UTC reset. Logged at
                // info level purely for diagnostic visibility, not error,
                // since this isn't something worth alarming over.
                AppLogger.shared.info("AppDelegate: launch-time staleness fetch skipped — quota already exhausted for the affected key(s)")
            case .notStale:
                break
            }
        }
        // Deliberately NOT scheduling the worker task here — per direct
        // instruction, no jobs should be scheduled by default on a fresh
        // launch. SettingsViewModel.reloadQuotaTimes() is the real
        // scheduling path: it runs once when Settings first appears
        // (load()) and again on every subsequent settings change, both
        // meaningful moments with real, current config/location already
        // in hand — not an unconditional attempt on every single cold
        // start regardless of whether the user has configured or changed
        // anything yet.
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}
