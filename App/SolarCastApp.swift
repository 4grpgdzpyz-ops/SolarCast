import SwiftUI
import SwiftData
@main struct SolarCastApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeStore = ThemeStore()
    @State private var hasRunLaunchFetch = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: DIContainer.shared.makeDashboardViewModel())
                .preferredColorScheme(themeStore.colorScheme)
                .environment(themeStore)
                .onAppear {
                    themeStore.applyOnLaunch()
                    appLog("SolarCast launched", level: .info)
                }
        }
        .modelContainer(DIContainer.shared.modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await BadgeManager.shared.clear() }
                // Launch-time staleness fetch — moved here from AppDelegate's
                // own didFinishLaunchingWithOptions, where applicationState
                // was found to sometimes not yet genuinely reflect .active
                // even on a real, user-initiated launch (iOS hadn't finished
                // settling the actual state transition that early in the
                // launch sequence), silently skipping fetches that should
                // have run. scenePhase's own transition to .active, reacted
                // to here via .onChange, is the more reliable, real signal —
                // and only fires for a genuine foreground appearance,
                // correctly staying silent for an OS-initiated
                // background-task launch, since that never transitions
                // scenePhase to .active at all unless the user also,
                // separately, brings the app to the foreground themselves.
                if !hasRunLaunchFetch {
                    hasRunLaunchFetch = true
                    Task {
                        let result = await DIContainer.shared.performAppLaunchFetchIfNeeded()
                        switch result {
                        case .fetchedSuccessfully:
                            NotificationCenter.default.post(name: .forecastDataRefreshed, object: nil)
                        case .fetchFailed(let error):
                            AppLogger.shared.error("SolarCastApp: launch-time staleness fetch failed: \(error.humanReadableMessage)")
                            NotificationCenter.default.post(name: .forecastDataRefreshed, object: nil,
                                                             userInfo: ["errorMessage": error.humanReadableMessage])
                        case .quotaExhausted:
                            AppLogger.shared.info("SolarCastApp: launch-time staleness fetch skipped — quota already exhausted for the affected key(s)")
                        case .notStale:
                            break
                        }
                    }
                }
            }
        }
    }
}
