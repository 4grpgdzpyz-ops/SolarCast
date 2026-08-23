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
        // Launch-time staleness check moved to SolarCastApp's own
        // .onChange(of: scenePhase), checked against the transition to
        // .active there instead of applicationState here — see
        // SolarCastApp.swift for the real, complete logic and reasoning.
        // applicationState, checked this early inside
        // didFinishLaunchingWithOptions, was found to
        // sometimes not yet reflect .active even on a genuine,
        // user-initiated launch (iOS hadn't finished the real state
        // transition yet at this exact point), silently skipping fetches
        // that should have run. scenePhase, reacted to via
        // .onChange(of: scenePhase) there, is a more reliable, real
        // signal for this.
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

    // Static tracking property — the app is portrait-only by default;
    // the fullscreen chart is the one real exception, widening this to
    // .landscape while presented and locking it back to .portrait on
    // exit.
    static var allowedOrientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.allowedOrientations
    }
}
