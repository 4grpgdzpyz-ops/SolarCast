import SwiftUI
import SwiftData
@main struct SolarCastApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeStore = ThemeStore()
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
            }
        }
    }
}
