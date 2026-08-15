import Foundation
actor ManageQuotaUseCase {
    private let apiKeyRepository: APIKeyRepository
    private let pvSiteRepository: PVSiteRepository
    private let quotaManager: QuotaManager
    private let schedulingEngine: SchedulingEngine

    init(apiKeyRepository: APIKeyRepository, pvSiteRepository: PVSiteRepository,
         quotaManager: QuotaManager, schedulingEngine: SchedulingEngine) {
        self.apiKeyRepository = apiKeyRepository; self.pvSiteRepository = pvSiteRepository
        self.quotaManager = quotaManager; self.schedulingEngine = schedulingEngine
    }

    func globalStats(fetchTriggerConfig: FetchTriggerConfiguration,
                     location: UserLocation?, now: Date = Date()) async throws -> GlobalQuotaStats {
        let keys  = try await apiKeyRepository.fetchAll()
        let sites = try await pvSiteRepository.fetchAll()

        // Compute auto-fetch time (global — same for all keys)
        var nextFetch: Date?
        if let loc = location {
            nextFetch = await schedulingEngine.nextAutoFetchTime(
                config: fetchTriggerConfig, location: loc, now: now)
        }

        var perKey: [QuotaStats] = []
        for key in keys {
            let assignedSites = sites.filter { $0.apiKeyID == key.id }
            let names = assignedSites.map(\.name)
            let siteCount = assignedSites.count

            // Compute next refresh PER KEY based on its own quota and
            // assigned sites — but only for ENABLED keys, matching
            // SchedulingEngine.nextScheduledFetch's own .filter(\.isEnabled).
            // A disabled key's own computed refresh time (likely earlier,
            // different quota state) could otherwise win the .min()
            // aggregation downstream in SettingsViewModel and be shown as
            // if it were the real, active schedule.
            var nextRefresh: Date?
            var nextRefreshInterval: Int?
            if key.isEnabled, let loc = location, siteCount > 0 {
                let result = await schedulingEngine.nextAutoRefreshTime(
                    config: fetchTriggerConfig, location: loc, apiKeyID: key.id,
                    dailyQuotaLimit: key.dailyQuotaLimit,
                    assignedSiteCount: siteCount, now: now)
                nextRefresh = result?.date
                nextRefreshInterval = result?.intervalMinutes
            }

            perKey.append(try await quotaManager.currentStats(
                apiKey: key, assignedSiteNames: names,
                nextAutoFetchTime: nextFetch, nextAutoRefreshTime: nextRefresh,
                nextAutoRefreshIntervalMinutes: nextRefreshInterval, now: now))
        }
        return GlobalQuotaStats(perKey: perKey)
    }
}
