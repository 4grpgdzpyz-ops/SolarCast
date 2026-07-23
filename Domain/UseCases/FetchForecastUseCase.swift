enum FetchError: LocalizedError {
    case noLocationConfigured
    case noSitesConfigured
    case noAPIKeyAssigned
    case quotaExhaustedForAllKeys
    case noSunWindowResolved

    var errorDescription: String? {
        switch self {
        case .noLocationConfigured:    return "No location set. Go to Settings → Location to configure it."
        case .noSitesConfigured:       return "No PV sites configured. Add a site in Settings → PV Sites."
        case .noAPIKeyAssigned:        return "No API key assigned to your sites. Go to Settings → API Keys."
        case .quotaExhaustedForAllKeys: return "Daily API quota reached. Calls will resume tomorrow."
        case .noSunWindowResolved:     return "Could not calculate sunrise/sunset for your location."
        }
    }
}

import Foundation
actor FetchForecastUseCase {
    private let apiKeyRepository: APIKeyRepository
    private let pvSiteRepository: PVSiteRepository
    private let forecastRepository: ForecastRepository
    private let locationRepository: LocationRepository
    private let quotaManager: QuotaManager
    private let sunWindowCalculator: SunWindowCalculator
    private let parallelFetchCoordinator: ParallelFetchCoordinator
    init(apiKeyRepository: APIKeyRepository, pvSiteRepository: PVSiteRepository,
         forecastRepository: ForecastRepository, locationRepository: LocationRepository,
         quotaManager: QuotaManager, sunWindowCalculator: SunWindowCalculator,
         parallelFetchCoordinator: ParallelFetchCoordinator) {
        self.apiKeyRepository = apiKeyRepository; self.pvSiteRepository = pvSiteRepository
        self.forecastRepository = forecastRepository; self.locationRepository = locationRepository
        self.quotaManager = quotaManager; self.sunWindowCalculator = sunWindowCalculator
        self.parallelFetchCoordinator = parallelFetchCoordinator
    }
    func executeAutoFetch() async throws { try await execute(purpose: .autoFetch) }
    /// If apiKeyID is provided, restricts execution to just that key's
    /// assigned sites — used when a specific key's own computed refresh
    /// interval is what triggered this call, so OTHER enabled keys (whose
    /// own intervals haven't elapsed yet) aren't touched. nil preserves
    /// the previous behavior (every eligible site) for any caller that
    /// doesn't know which key triggered it.
    func executeAutoRefresh(apiKeyID: UUID? = nil) async throws {
        guard let apiKeyID else {
            try await execute(purpose: .autoRefresh)
            return
        }
        let siteIDs = try await pvSiteRepository.fetchAll()
            .filter { $0.apiKeyID == apiKeyID }.map(\.id)
        try await execute(purpose: .autoRefresh, restrictToSiteIDs: siteIDs)
    }
    func executeManual(siteIDs: [UUID]? = nil) async throws { try await execute(purpose: .manual, restrictToSiteIDs: siteIDs) }
    /// What actually happened when checking for launch-time staleness.
    /// Previously this returned a plain Bool that conflated two genuinely
    /// different things: "nothing was stale" and "something was stale but
    /// the fetch failed" both produced the same `false`/no-signal result —
    /// worse, the fetch's own thrown error was caught via try? and then
    /// the function unconditionally returned true immediately after,
    /// meaning a REAL FAILURE was reported to callers as success. Callers
    /// (AppDelegate, DashboardView) showed a "Data Refreshed" alert on a
    /// failed fetch, or showed nothing at all for a failure that happened
    /// before execute() was even called — no way to distinguish "was
    /// fresh" from "tried and failed" from the return value alone.
    enum StalenessCheckResult {
        case notStale
        case fetchedSuccessfully
        case fetchFailed(Error)
        /// Something WAS genuinely stale, but the fetch was deliberately
        /// skipped because the affected key's daily quota is already
        /// exhausted — distinct from .notStale (nothing needed doing at
        /// all) even though both are treated the same at the UI layer
        /// (no alert shown either way). Showing a "quota exhausted"
        /// failure every single time the app comes to the foreground,
        /// for a condition that's expected to persist until the next
        /// UTC reset, would be genuinely unhelpful noise, not a real,
        /// actionable failure the user needs to see repeatedly.
        case quotaExhausted
    }

    /// Checks per-key staleness (see StalenessEvaluator) and, if any enabled
    /// key is stale, fetches only that key's assigned sites — not every
    /// site, and not every key. Fresh keys are left untouched for this cycle.
    ///
    /// onWillFetch is awaited exactly once, only if staleness genuinely
    /// requires a fetch, right before that fetch starts — never during the
    /// staleness check itself, and never for a .notStale outcome. It's
    /// `async` specifically so the caller's state mutation (e.g. setting
    /// isRefreshing = true on the main actor) is guaranteed to complete
    /// before this function proceeds to the real fetch or returns — a
    /// fire-and-forget Task from inside a synchronous closure would have no
    /// ordering guarantee against the caller's own subsequent code, risking
    /// isRefreshing being set true AFTER the caller had already reset it to
    /// false. This is what lets a caller (DashboardView) show a
    /// "refreshing" indicator scoped to the real fetch only, instead of the
    /// whole check-then-maybe-fetch sequence: previously the caller had no
    /// way to distinguish "still evaluating whether anything is stale" from
    /// "confirmed stale, actually fetching now."
    @discardableResult
    func executeAppLaunchIfStale(schedulingEngine: SchedulingEngine, bgTaskCoordinator: BGTaskCoordinator, onWillFetch: (() async -> Void)? = nil) async throws -> StalenessCheckResult {
        let keys = try await apiKeyRepository.fetchAll()
        guard let location = try await locationRepository.fetchCurrent() else { return .notStale }
        let config = FetchTriggerConfigurationStore.load()

        let staleKeyIDs = await schedulingEngine.staleAPIKeys(
            apiKeys: keys, config: config, location: location)
        guard !staleKeyIDs.isEmpty else { return .notStale }

        let staleSiteIDs = try await pvSiteRepository.fetchAll()
            .filter { site in site.apiKeyID.map(staleKeyIDs.contains) ?? false }
            .map(\.id)
        guard !staleSiteIDs.isEmpty else { return .notStale }

        // Staleness is now genuinely confirmed — this is the one moment
        // onWillFetch fires, awaited to completion before the real fetch
        // begins.
        await onWillFetch?()

        // The fetch itself is still allowed to fail without THROWING out of
        // this function (a launch-time config issue shouldn't crash the
        // app) — but the real outcome is now preserved and returned,
        // rather than discarded and replaced with an unconditional true.
        let result: StalenessCheckResult
        do {
            try await execute(purpose: .appLaunchStaleness, restrictToSiteIDs: staleSiteIDs)
            result = .fetchedSuccessfully
        } catch FetchError.quotaExhaustedForAllKeys {
            // Something WAS genuinely stale, but every affected key's
            // quota is already exhausted for the day — deliberately NOT
            // treated as a real, actionable failure the user needs to
            // see. This condition is expected to persist until the next
            // UTC reset; surfacing it as a failure alert every single
            // time the app comes to the foreground in the meantime would
            // be repetitive noise, not useful information.
            result = .quotaExhausted
        } catch {
            result = .fetchFailed(error)
        }
        // Genuinely changed quota usage either way — the actual mutation
        // (recordUsage, and for a real 429, forceQuotaExhausted) already
        // happened inside execute() regardless of whether it ultimately
        // threw, so reschedule and notify unconditionally here, not just
        // on the success path above.
        await bgTaskCoordinator.scheduleNext(config: config, location: location)
        await MainActor.run {
            NotificationCenter.default.post(name: .quotaAffectingRescheduleOccurred, object: nil)
        }
        return result
    }
    private func execute(purpose: FetchPurpose, restrictToSiteIDs: [UUID]? = nil, now: Date = Date()) async throws {
        appLog("Fetch starting — purpose=\(purpose.rawValue)")
        let allKeys = try await apiKeyRepository.fetchAll()
        let allSites = try await pvSiteRepository.fetchAll()
        guard try await locationRepository.fetchCurrent() != nil else {
            AppLogger.shared.stepFailed(1, "No location configured")
            throw FetchError.noLocationConfigured
        }
        AppLogger.shared.step(1, "Location OK")
        let eligible = restrictToSiteIDs.map { ids in allSites.filter { ids.contains($0.id) } } ?? allSites
        if eligible.isEmpty {
            AppLogger.shared.stepFailed(2, "No sites configured")
            throw FetchError.noSitesConfigured
        }
        AppLogger.shared.step(2, "\(eligible.count) eligible sites")
        var jobs: [FetchJob] = []
        var hasUnassigned = true
        var allQuotaExhausted = true
        for site in eligible {
            guard let kid = site.apiKeyID, let key = allKeys.first(where: { $0.id == kid }) else { continue }
            hasUnassigned = false
            if try await quotaManager.canMakeCall(apiKey: key, purpose: purpose, now: now) {
                allQuotaExhausted = false
                jobs.append(FetchJob(pvSite: site, apiKey: key))
            }
        }
        AppLogger.shared.step(3, "\(jobs.count) jobs queued")
        if jobs.isEmpty {
            if hasUnassigned {
                AppLogger.shared.stepFailed(3, "No API key assigned")
                throw FetchError.noAPIKeyAssigned
            }
            // Only throw quota error for manual/launch fetches — background tasks
            // return silently so the OS doesn't penalize the app for task failure.
            if allQuotaExhausted {
                switch purpose {
                case .manual, .appLaunchStaleness, .imported, .rateLimitCorrection: throw FetchError.quotaExhaustedForAllKeys
                case .autoFetch, .autoRefresh: return
                }
            }
            return
        }
        AppLogger.shared.step(4, "Executing \(jobs.count) parallel fetches")
        var lastNetworkError: NetworkError?
        let results = await parallelFetchCoordinator.execute(jobs: jobs)
        AppLogger.shared.step(5, "Received \(results.count) results")
        for result in results {
            switch result {
            case .success(let sid, let dtos):
                guard let job = jobs.first(where: { $0.pvSite.id == sid }) else { continue }
                let isMock = parallelFetchCoordinator.apiClient is MockSolcastAPIClient
                // Record quota BEFORE upsert so it's always debited even if persistence fails
                try await quotaManager.recordUsage(apiKeyID: job.apiKey.id, wasSuccessful: true, purpose: purpose, isMock: isMock, now: now)
                do {
                    let (pts, mapErrors) = ForecastPointMapper.mapBatch(dtos: dtos, pvSiteID: sid, isMock: isMock)
                    if !mapErrors.isEmpty {
                        AppLogger.shared.warn("\(mapErrors.count) mapping errors for site \(sid): \(mapErrors)")
                    }
                    // Do NOT filter by sun window at ingestion — store all points so
                    // future dates have data. Sun window filtering happens at display
                    // time inside ComputeStatsUseCase and BuildChartDataUseCase.
                    if !pts.isEmpty {
                        AppLogger.shared.info("Upserting \(pts.count) points for site \(sid)")
                        // Bounded retry specifically around persistence, not the
                        // network call or quota recording. Quota is deliberately
                        // recorded before this point (see above) because the real
                        // network call to Solcast already happened and already
                        // counted against Solcast's own server-side quota,
                        // regardless of what happens locally afterward — reordering
                        // to record quota only after a successful persist would let
                        // the app think it has quota remaining that Solcast's
                        // servers already consider spent, risking a genuine
                        // over-quota call on Solcast's side. This retry instead
                        // targets the actual reported symptom (a persistence
                        // failure right after a successful, quota-consuming fetch,
                        // that only resolved itself on the NEXT scheduled cycle) —
                        // giving persistence one immediate second chance rather than
                        // silently failing and waiting for whatever triggers the
                        // next fetch, which could be hours away.
                        var persistError: Error?
                        for attempt in 1...2 {
                            do {
                                try await forecastRepository.upsert(points: pts)
                                AppLogger.shared.info("Upserted \(pts.count) points for site \(sid)\(attempt > 1 ? " (succeeded on retry)" : "")")
                                persistError = nil
                                break
                            } catch {
                                persistError = error
                                if attempt == 1 {
                                    AppLogger.shared.warn("Persistence attempt 1 failed for site \(sid), retrying once: \(error.localizedDescription)")
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                }
                            }
                        }
                        if let persistError {
                            // Both attempts failed — log with full detail (not just
                            // localizedDescription) so a recurring failure is
                            // actually diagnosable, since this is exactly the
                            // failure mode that produces "quota consumed, no data."
                            AppLogger.shared.error("Persistence failed for site \(sid) after 2 attempts: \(persistError)")
                        }
                    } else {
                        AppLogger.shared.warn("No points mapped for site \(sid) (\(dtos.count) DTOs received, \(mapErrors.count) mapping errors)")
                    }
                } catch {
                    // Log persistence errors — these are non-fatal but important to see
                    AppLogger.shared.error("Persistence error for site \(sid): \(error.localizedDescription)")
                }
            case .failure(let sid, let fetchError):
                guard let job = jobs.first(where: { $0.pvSite.id == sid }) else { continue }
                AppLogger.shared.error("Fetch error for site \(sid): \(fetchError)")
                let isMockFailure = parallelFetchCoordinator.apiClient is MockSolcastAPIClient
                // Only invalidURL/noConnectivity are genuinely LOCAL
                // failures that never reached Solcast's server at all —
                // every other real failure (rate limited, unauthorized,
                // server error, decode failure, unknown status) IS a
                // real network round-trip that almost certainly still
                // counts against the real, server-side daily quota,
                // even though it wasn't successful.
                let consumedRealCall: Bool
                switch fetchError {
                case .invalidURL, .noConnectivity: consumedRealCall = false
                default: consumedRealCall = true
                }
                try await quotaManager.recordUsage(apiKeyID: job.apiKey.id, wasSuccessful: false, purpose: purpose, isMock: isMockFailure, consumedRealCall: consumedRealCall, now: now)
                if case .rateLimited = fetchError {
                    // Solcast itself just said the real, server-side
                    // quota is exhausted — force this key's LOCAL count
                    // to match reality immediately, rather than let this
                    // app keep believing calls remain and attempt (and
                    // fail) more real requests before its own count
                    // naturally catches up.
                    try await quotaManager.forceQuotaExhausted(apiKey: job.apiKey, isMock: isMockFailure, now: now)
                }
                lastNetworkError = fetchError
            }
        }
        let successCount = results.filter { if case .success = $0 { return true }; return false }.count
        if successCount == 0, let err = lastNetworkError {
            throw err
        }
        // Filter out last forecast day if incomplete (doesn't cover full sun window)
        if successCount > 0 {
            await filterIncompleteLastDay(now: now)
        }
    }

    private func filterIncompleteLastDay(now: Date) async {
        do {
            let cal = Calendar.current
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
            let todayStr = fmt.string(from: now)
            // Get all sites
            let sites = try await pvSiteRepository.fetchAll()
            guard !sites.isEmpty else { return }
            // Fetch all future points
            let futureStart = cal.startOfDay(for: now.addingTimeInterval(86400))
            let farFuture = now.addingTimeInterval(86400 * 10)
            let points = try await forecastRepository.fetchPoints(
                pvSiteIDs: sites.map(\.id), from: futureStart, to: farFuture)
            guard !points.isEmpty else { return }
            // Group by date
            let byDate = Dictionary(grouping: points) { fmt.string(from: $0.periodStart) }
            let sortedDates = byDate.keys.sorted()
            guard let lastDate = sortedDates.last, lastDate > todayStr else { return }
            // Check if last day has enough coverage
            let lastDayPts = byDate[lastDate] ?? []
            guard !lastDayPts.isEmpty else { return }
            let lastPoint = lastDayPts.max(by: { $0.periodEnd < $1.periodEnd })!
            let lastHour = cal.component(.hour, from: lastPoint.periodEnd)
            // If last data point is before 17:00 local, the day is incomplete — delete it
            if lastHour < 17 {
                AppLogger.shared.info("Filtering incomplete last forecast day: \(lastDate) (last point hour: \(lastHour))")
                try await forecastRepository.deletePoints(matching: lastDayPts.map(\.id))
            }
        } catch {
            AppLogger.shared.warn("Failed to filter incomplete last day: \(error)")
        }
    }
}
