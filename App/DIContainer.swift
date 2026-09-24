import Foundation
import SwiftData

/// Composition root — constructs and wires every repository, use case, and
/// coordinator the app needs, in dependency order.
///
/// IMPORTANT init-ordering constraint: properties are constructed in
/// DECLARATION order within init(), and several later properties depend on
/// earlier ones already existing (e.g. MockSolcastAPIClient's init needs
/// sunWindowCalculator, pvSiteRepository, and apiKeyRepository already
/// constructed; SchedulingEngine needs apiKeyRepository). When adding a
/// new dependency here, check what it needs BEFORE placing its
/// construction line — this has been a real, repeated source of build
/// errors when a new property was added below something it actually
/// depends on.
final class DIContainer {
    static let shared = DIContainer()
    let modelContainer: ModelContainer
    private let forecastRepository: ForecastRepository
    private let pvSiteRepository: PVSiteRepository
    let apiKeyRepository: APIKeyRepository
    private let quotaRepository: QuotaRepository
    private let locationRepository: LocationRepository
    private var apiClient: SolcastAPIClientProtocol
    private var parallelFetchCoordinator: ParallelFetchCoordinator
    let sunWindowCalculator: SunWindowCalculator
    let quotaManager: QuotaManager
    let schedulingEngine: SchedulingEngine
    let backupService: BackupService
    /// Exposed so DashboardViewModel always gets the current (possibly mock-swapped) instance
    var themeStore: ThemeStore?
    private(set) var currentFetchUseCase: FetchForecastUseCase
    private let computeStatsUseCase: ComputeStatsUseCase
    private let buildChartDataUseCase: BuildChartDataUseCase
    private let manageQuotaUseCase: ManageQuotaUseCase
    private init() {
        // Fall back to in-memory store if the on-disk container fails (e.g. schema
        // mismatch after an update). Data won't persist across launches in this state,
        // but the app remains usable rather than crashing.
        do { modelContainer = try ModelContainerFactory.makeLiveContainer() }
        catch {
            AppLogger.shared.warn("On-disk SwiftData store failed (\(error)). Falling back to in-memory.")
            modelContainer = try! ModelContainerFactory.makeInMemoryContainer()
        }
        forecastRepository  = SwiftDataForecastRepository(modelContainer: modelContainer)
        pvSiteRepository    = SwiftDataPVSiteRepository(modelContainer: modelContainer)
        apiKeyRepository    = SwiftDataAPIKeyRepository(modelContainer: modelContainer)
        quotaRepository     = SwiftDataQuotaRepository(modelContainer: modelContainer)
        locationRepository  = SwiftDataLocationRepository(modelContainer: modelContainer)
        sunWindowCalculator = SunWindowCalculator(solarCalculator: ceeKSolarAdapter())
        if UserDefaults.standard.bool(forKey: "solarcast.useMockData") {
            apiClient = MockSolcastAPIClient(locationRepository: locationRepository, sunWindowCalculator: sunWindowCalculator,
                pvSiteRepository: pvSiteRepository, apiKeyRepository: apiKeyRepository)
            appLog("DIContainer: using MockSolcastAPIClient (mock mode enabled)")
        } else {
            apiClient = SolcastAPIClient()
        }
        parallelFetchCoordinator = ParallelFetchCoordinator(apiClient: apiClient)
        quotaManager        = QuotaManager(quotaRepository: quotaRepository)
        schedulingEngine    = SchedulingEngine(sunWindowCalculator: sunWindowCalculator,
            forecastRepository: forecastRepository, quotaRepository: quotaRepository,
            pvSiteRepository: pvSiteRepository, apiKeyRepository: apiKeyRepository)
        backupService       = BackupService(modelContainer: modelContainer)
        currentFetchUseCase = FetchForecastUseCase(
            apiKeyRepository: apiKeyRepository, pvSiteRepository: pvSiteRepository,
            forecastRepository: forecastRepository, locationRepository: locationRepository,
            quotaManager: quotaManager, sunWindowCalculator: sunWindowCalculator,
            parallelFetchCoordinator: parallelFetchCoordinator)
        computeStatsUseCase = ComputeStatsUseCase(
            forecastRepository: forecastRepository, pvSiteRepository: pvSiteRepository,
            apiKeyRepository: apiKeyRepository, locationRepository: locationRepository,
            sunWindowCalculator: sunWindowCalculator)
        buildChartDataUseCase = BuildChartDataUseCase(
            forecastRepository: forecastRepository, pvSiteRepository: pvSiteRepository,
            apiKeyRepository: apiKeyRepository, locationRepository: locationRepository,
            sunWindowCalculator: sunWindowCalculator)
        manageQuotaUseCase = ManageQuotaUseCase(
            apiKeyRepository: apiKeyRepository, pvSiteRepository: pvSiteRepository,
            quotaManager: quotaManager, schedulingEngine: schedulingEngine)
    }
    /// Hot-swap the API client when mock mode is toggled — no restart needed.
    /// Also purges any stored forecast data from the OTHER source, so
    /// switching mock<->real never leaves the two mixed in the same
    /// site/timestamp slots (which previously happened silently, since
    /// upsert only keys on site+time, not on where the data came from).
    func reloadAPIClient() async {
        let useMock = UserDefaults.standard.bool(forKey: "solarcast.useMockData")
        if useMock {
            apiClient = MockSolcastAPIClient(locationRepository: locationRepository, sunWindowCalculator: sunWindowCalculator,
                pvSiteRepository: pvSiteRepository, apiKeyRepository: apiKeyRepository)
            appLog("DIContainer: switched to MockSolcastAPIClient (mock mode ON)")
            // Nothing is deleted here. The old design deleted REAL data the
            // instant mock was enabled (deleteAllPoints(isMock: !useMock)
            // with useMock=true evaluates to deleteAllPoints(isMock:
            // false)) — a real bug, since the Settings confirmation
            // dialog's own wording ("switch...instead of") promised
            // reversibility that never actually held. Mock and real data
            // now coexist safely in storage while mock is ON:
            // SwiftDataForecastRepository.fetchPoints filters reads by the
            // CURRENT mode, so only mock records are ever displayed while
            // this mode is active, without touching real data at all.
        } else {
            apiClient = SolcastAPIClient()
            appLog("DIContainer: switched to SolcastAPIClient (mock mode OFF)")
            // Deliberately ONE-DIRECTIONAL cleanup, only on DISABLING mock:
            // every mock record is deleted unconditionally (no date/site
            // filtering — deleteAllPoints has none), per direct
            // instruction. This never touches real data, and mirrors the
            // old code's mistake in the opposite, intended direction only
            // — the old logic deleted the WRONG mode's data on the WRONG
            // transition; this deletes the RIGHT mode's data on the RIGHT
            // transition, and only that one.
            do { try await forecastRepository.deleteAllPoints(isMock: true) }
            catch { AppLogger.shared.error("Failed to purge mock forecast data on disabling mock mode: \(error)") }
            // Same reasoning, same transition, for quota usage events —
            // previously only forecast points were purged here, so
            // mock-mode QuotaUsageEvents (isMock: true) lingered in
            // storage indefinitely, merely hidden by fetchUsageEvents'
            // mode-aware read rather than actually removed.
            do { try await quotaRepository.deleteAllEvents(isMock: true) }
            catch { AppLogger.shared.error("Failed to purge mock quota usage data on disabling mock mode: \(error)") }
        }

        parallelFetchCoordinator = ParallelFetchCoordinator(apiClient: apiClient)
        currentFetchUseCase = FetchForecastUseCase(
            apiKeyRepository: apiKeyRepository, pvSiteRepository: pvSiteRepository,
            forecastRepository: forecastRepository, locationRepository: locationRepository,
            quotaManager: quotaManager, sunWindowCalculator: sunWindowCalculator,
            parallelFetchCoordinator: parallelFetchCoordinator)
    }

    @MainActor func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(computeStatsUseCase: computeStatsUseCase,
                           buildChartDataUseCase: buildChartDataUseCase,
                           manageQuotaUseCase: manageQuotaUseCase,
                           pvSiteRepository: pvSiteRepository,
                           forecastRepository: forecastRepository,
                           locationRepository: locationRepository)
    }
    @MainActor func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(apiKeyRepository: apiKeyRepository, pvSiteRepository: pvSiteRepository,
                          locationRepository: locationRepository, manageQuotaUseCase: manageQuotaUseCase)
    }
    @MainActor func makeAPIKeyEditViewModel(key: APIKey?) -> APIKeyEditViewModel {
        APIKeyEditViewModel(key: key, apiKeyRepository: apiKeyRepository, pvSiteRepository: pvSiteRepository)
    }
    @MainActor func makePVSiteEditViewModel(site: PVSite?) -> PVSiteEditViewModel {
        PVSiteEditViewModel(site: site, pvSiteRepository: pvSiteRepository)
    }
    @MainActor func makeLocationPickerViewModel() -> LocationPickerViewModel {
        LocationPickerViewModel(locationRepository: locationRepository)
    }
    func makeBGTaskCoordinator() -> BGTaskCoordinator {
        BGTaskCoordinator(fetchForecastUseCase: currentFetchUseCase, schedulingEngine: schedulingEngine)
    }
    func loadSchedulingContext() async -> (FetchTriggerConfiguration, UserLocation?)? {
        guard let loc = try? await locationRepository.fetchCurrent() else { return nil }
        return (FetchTriggerConfigurationStore.load(), loc)
    }
    @discardableResult
    /// Preserves the real outcome from executeAppLaunchIfStale instead of
    /// collapsing it back into a Bool — see StalenessCheckResult's own doc
    /// comment for why that collapsing was the actual bug being fixed
    /// here. A genuine repository-level throw (a local database failure,
    /// distinct from the fetch itself failing, which executeAppLaunchIfStale
    /// already catches internally as .fetchFailed) is also preserved as
    /// its own case rather than silently treated as "wasn't stale."
    func performAppLaunchFetchIfNeeded(onWillFetch: (() async -> Void)? = nil) async -> FetchForecastUseCase.StalenessCheckResult {
        do {
            return try await currentFetchUseCase.executeAppLaunchIfStale(
                schedulingEngine: schedulingEngine, bgTaskCoordinator: makeBGTaskCoordinator(), onWillFetch: onWillFetch)
        } catch {
            AppLogger.shared.error("DIContainer: executeAppLaunchIfStale threw unexpectedly: \(error)")
            return .fetchFailed(error)
        }
    }
}
