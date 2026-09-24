import Foundation
import Observation

@Observable final class SettingsViewModel {
    private let apiKeyRepository: APIKeyRepository
    private let pvSiteRepository: PVSiteRepository
    private let locationRepository: LocationRepository
    private let manageQuotaUseCase: ManageQuotaUseCase

    var autoFetchEnabled: Bool = true {
        didSet { persistConfig() }
    }
    var autoFetchTiming: FetchTriggerConfiguration.AutoFetchTiming = .sunriseRelative(offsetMinutes: -30) {
        didSet { persistConfig() }
    }
    var autoRefreshEnabled: Bool = false {
        didSet { persistConfig() }
    }
    var computedRefreshIntervalMinutes: Int?
    var nextAutoFetchTime: Date?
    var nextAutoRefreshTime: Date?
    var apiKeys: [APIKey] = []
    var sites: [PVSite] = []
    var location: UserLocation?
    var quotaStats: GlobalQuotaStats?
    var isLoading = false
    var errorMessage: String?
    var settingsVersion = UUID()

    /// Cancelled and restarted on every persistConfig() call — collapses a
    /// burst of rapid assignments (e.g. DatePicker/Stepper firing their
    /// binding's set{} multiple times across one continuous user gesture)
    /// into a single actual save/log line once the user stops interacting,
    /// instead of one save per intermediate value.
    private var persistDebounceTask: Task<Void, Never>?

    init(
        apiKeyRepository: APIKeyRepository,
        pvSiteRepository: PVSiteRepository,
        locationRepository: LocationRepository,
        manageQuotaUseCase: ManageQuotaUseCase
    ) {
        self.apiKeyRepository = apiKeyRepository
        self.pvSiteRepository = pvSiteRepository
        self.locationRepository = locationRepository
        self.manageQuotaUseCase = manageQuotaUseCase
        // _autoFetchEnabled etc. (the underlying storage @Observable
        // generates) is set directly here, NOT through the observed
        // property itself — assigning through autoFetchEnabled/
        // autoFetchTiming/autoRefreshEnabled would each fire didSet ->
        // persistConfig(), writing the just-loaded value straight back to
        // storage and logging "Settings changed" 3 times on every single
        // SettingsViewModel construction (i.e. every time Settings is
        // opened), with zero actual user edits involved. That was the
        // dominant source of repeated same-second log lines.
        let saved = FetchTriggerConfigurationStore.load()
        _autoFetchEnabled   = saved.autoFetchEnabled
        _autoFetchTiming    = saved.autoFetchTiming
        _autoRefreshEnabled = saved.autoRefreshEnabled
    }

    private func persistConfig() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms quiet period
            guard !Task.isCancelled, let self else { return }
            FetchTriggerConfigurationStore.save(self.currentConfig())
            self.settingsVersion = UUID()
            // Recompute next fetch/refresh times immediately
            await self.reloadQuotaTimes()
        }
    }

    func reloadQuotaTimes() async {
        do {
            let loc = try? await locationRepository.fetchCurrent()
            quotaStats = try await manageQuotaUseCase.globalStats(
                fetchTriggerConfig: currentConfig(), location: loc)
            nextAutoFetchTime   = quotaStats?.perKey.first?.nextAutoFetchTime
            nextAutoRefreshTime = quotaStats?.perKey.compactMap({ $0.nextAutoRefreshTime }).min()
            computedRefreshIntervalMinutes = quotaStats?.perKey.compactMap({ $0.nextAutoRefreshIntervalMinutes }).min()

            // The real scheduling trigger point: min(auto-fetch,
            // auto-refresh, log cleanup) is computed inside
            // SchedulingEngine.nextScheduledFetch (called via
            // BGTaskCoordinator.scheduleNext), each independently gated
            // on its own enabled state. This is the moment real, current
            // config and location are already in hand — same directness
            // that makes toggle-driven scheduling reliable, no separate
            // async app-launch gate to silently fail first.
            if let loc {
                await DIContainer.shared.makeBGTaskCoordinator().scheduleNext(config: currentConfig(), location: loc)
            } else {
                AppLogger.shared.info("SettingsViewModel: reloadQuotaTimes skipped scheduling — no location available")
            }
        } catch {
            AppLogger.shared.error("SettingsViewModel: failed to reload quota times: \(error)")
        }
    }

    func currentConfig() -> FetchTriggerConfiguration {
        FetchTriggerConfiguration(
            autoFetchEnabled: autoFetchEnabled,
            autoFetchTiming: autoFetchTiming,
            autoRefreshEnabled: autoRefreshEnabled)
    }

    func clearLocation() async {
        do {
            try await locationRepository.delete()
            location = nil
            settingsVersion = UUID()
        } catch {
            AppLogger.shared.error("SettingsViewModel: failed to clear location: \(error)")
            errorMessage = "Couldn't clear location."
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Re-read preferences from UserDefaults (needed after import)
        let savedConfig = FetchTriggerConfigurationStore.load()
        // Assigning through autoFetchEnabled/autoFetchTiming/
        // autoRefreshEnabled directly would each fire didSet ->
        // persistConfig(), independently scheduling a SECOND, debounced,
        // CONCURRENT call to reloadQuotaTimes() — racing against this
        // function's own explicit call to it a few lines below.
        // Whichever finishes last silently overwrites the other's
        // result, with no guarantee it used correct, current inputs.
        // This was already identified and fixed for init() (see the
        // comment there) but load() — called separately, on every
        // Settings sheet presentation — had the identical bug and never
        // received the same fix. Using the underlying @Observable
        // storage directly bypasses didSet, exactly as init() does.
        _autoFetchEnabled = savedConfig.autoFetchEnabled
        _autoFetchTiming = savedConfig.autoFetchTiming
        _autoRefreshEnabled = savedConfig.autoRefreshEnabled

        do {
            apiKeys  = try await apiKeyRepository.fetchAll()
            sites    = try await pvSiteRepository.fetchAll()
            location = try await locationRepository.fetchCurrent()
            // Consolidated into reloadQuotaTimes() — that's the one place
            // real scheduling now happens. Without this, load() would be a
            // separate, unfixed path that never actually schedules the
            // worker task — only persistConfig()'s own call to
            // reloadQuotaTimes() would, meaning the job would only ever
            // get submitted after the user actively changed a setting,
            // never on first opening Settings.
            await reloadQuotaTimes()
            settingsVersion = UUID()
        } catch {
            AppLogger.shared.error("SettingsViewModel: failed to load settings: \(error)")
            errorMessage = "Couldn't load settings."
        }
    }

    /// Approximates SchedulingEngine.nextScheduledFetch's real semantics:
    /// with more than one enabled key, the actual background schedule is
    /// driven by whichever key's own computed refresh produces the
    /// EARLIEST next Date, not simply "the first enabled key found." This
    /// used to only consider apiKeys.first(where: isEnabled), which could
    /// display a different (and incorrect) interval on this screen than
    /// what SchedulingEngine would actually use for a user with multiple
    /// enabled keys.
    ///
    /// This is still an approximation, not identical to SchedulingEngine's
    /// computation: taking the minimum INTERVAL across keys isn't exactly
    /// the same as taking the minimum next-refresh DATE, since two keys
    /// with different last-refresh timestamps but the same interval could
    /// have different actual next-refresh times. computedRefreshIntervalMinutes
    /// is a display value ("about every N minutes"), not a promise of the
    /// exact next refresh time — nextAutoRefreshTime (computed separately,
    /// via ManageQuotaUseCase) is the actual per-key Date-based value.
    func updateDailyLimit(for keyID: UUID, to newLimit: Int) async {
        guard var key = apiKeys.first(where: { $0.id == keyID }) else { return }
        key.dailyQuotaLimit = max(0, newLimit)
        do {
            try await apiKeyRepository.save(key)
            AppLogger.shared.info("Settings changed: key '\(key.name)' daily limit -> \(key.dailyQuotaLimit)")
            await load()
        }
        catch {
            AppLogger.shared.error("SettingsViewModel: failed to update quota limit for key '\(key.name)': \(error)")
            errorMessage = "Couldn't update quota limit."
        }
    }

    func toggleKeyEnabled(_ keyID: UUID) async {
        guard var key = apiKeys.first(where: { $0.id == keyID }) else { return }
        key.isEnabled.toggle()
        do {
            try await apiKeyRepository.save(key)
            AppLogger.shared.info("Settings changed: key '\(key.name)' enabled -> \(key.isEnabled)")
            await load()
        }
        catch {
            AppLogger.shared.error("SettingsViewModel: failed to toggle key '\(key.name)' enabled state: \(error)")
            errorMessage = "Couldn't update key."
        }
    }

    func deleteKey(_ keyID: UUID) async {
        do {
            try await apiKeyRepository.delete(id: keyID)
            AppLogger.shared.info("Settings changed: deleted API key \(keyID)")
            await load()
        }
        catch {
            AppLogger.shared.error("SettingsViewModel: failed to delete API key \(keyID): \(error)")
            errorMessage = "Couldn't delete API key."
        }
    }

    func deleteSite(_ siteID: UUID) async {
        do {
            try await pvSiteRepository.delete(id: siteID)
            AppLogger.shared.info("Settings changed: deleted PV site \(siteID)")
            await load()
        }
        catch {
            AppLogger.shared.error("SettingsViewModel: failed to delete PV site \(siteID): \(error)")
            errorMessage = "Couldn't delete site."
        }
    }
}
