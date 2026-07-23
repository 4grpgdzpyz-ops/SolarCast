import Foundation
import Observation

@Observable final class DashboardViewModel {
    private let computeStatsUseCase: ComputeStatsUseCase
    private let buildChartDataUseCase: BuildChartDataUseCase
    private let manageQuotaUseCase: ManageQuotaUseCase
    /// Always reads from DIContainer so mock toggle takes effect immediately
    private var fetchForecastUseCase: FetchForecastUseCase { DIContainer.shared.currentFetchUseCase }
    private let pvSiteRepository: PVSiteRepository
    private let forecastRepository: ForecastRepository
    private let locationRepository: LocationRepository

    var selectedDate: Date = Date()
    var selectedScenario: Scenario = .normal
    var statsResult: StatsResult?
    var chartSeries: [ChartSeries] = []
    var quotaStats: GlobalQuotaStats?
    var sites: [PVSite] = []
    var apiKeys: [APIKey] = []
    var isRefreshing = false
    var isLoading = false
    var errorMessage: String?
    var hiddenSeriesIDs: Set<String> = []

    init(computeStatsUseCase: ComputeStatsUseCase, buildChartDataUseCase: BuildChartDataUseCase,
         manageQuotaUseCase: ManageQuotaUseCase,
         pvSiteRepository: PVSiteRepository,
         forecastRepository: ForecastRepository,
         locationRepository: LocationRepository) {
        self.computeStatsUseCase = computeStatsUseCase
        self.buildChartDataUseCase = buildChartDataUseCase
        self.manageQuotaUseCase = manageQuotaUseCase
        self.pvSiteRepository = pvSiteRepository
        self.forecastRepository = forecastRepository
        self.locationRepository = locationRepository
    }

    func loadAll() async {
        isLoading = true; defer { isLoading = false }
        // loadSites populates apiKeys/sites, used by activeSites (still
        // needed for the UI's own site list, e.g. SiteBreakdownCard) — but
        // stats/chart scoping to active sites now happens inside
        // ComputeStatsUseCase/BuildChartDataUseCase themselves, not here.
        await loadSites()
        async let s: Void = loadStats()
        async let c: Void = loadChart()
        async let q: Void = loadQuota()
        _ = await (s, c, q)
        await loadDatesWithData()
    }

    func loadStats() async {
        do { statsResult = try await computeStatsUseCase.execute(date: selectedDate, scenario: selectedScenario) }
        catch {
            AppLogger.shared.error("DashboardViewModel: failed to load stats: \(error)")
            errorMessage = "Couldn't load statistics."
        }
    }

    func loadChart() async {
        do {
            // buildChartDataUseCase now filters to active sites (assigned
            // to an enabled key) at the source — see ActiveSitePolicy —
            // so everything it returns, including "total", is already
            // correctly scoped. No further filtering needed here.
            chartSeries = try await buildChartDataUseCase.execute(date: selectedDate, scenario: selectedScenario)
        }
        catch {
            AppLogger.shared.error("DashboardViewModel: failed to load chart data: \(error)")
            errorMessage = "Couldn't load chart data."
        }
    }

    func loadSites() async {
        do {
            sites = try await pvSiteRepository.fetchAll()
            apiKeys = try await DIContainer.shared.apiKeyRepository.fetchAll()
        }
        catch {
            AppLogger.shared.error("DashboardViewModel: failed to load sites/keys: \(error)")
            errorMessage = "Couldn't load sites."
        }
    }

    private func filterIncompleteLastDay(_ dates: Set<String>, points: [ForecastPoint]) -> Set<String> {
        guard !dates.isEmpty else { return dates }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
        let todayStr = fmt.string(from: Date())
        var filtered = dates
        let sorted = dates.sorted()
        // Check all future dates — remove any where data doesn't span at least
        // from before 09:00 to after 17:00 local time (core solar hours)
        let cal = Calendar.current
        for dateStr in sorted where dateStr > todayStr {
            let dayPoints = points.filter { fmt.string(from: $0.periodStart) == dateStr }
                .sorted { $0.periodStart < $1.periodStart }
            guard let first = dayPoints.first, let last = dayPoints.last else {
                filtered.remove(dateStr); continue
            }
            let firstHour = cal.component(.hour, from: first.periodStart)
            let lastHour = cal.component(.hour, from: last.periodStart)
            // If data doesn't cover at least 09:00–17:00, it's incomplete
            if firstHour > 9 || lastHour < 17 {
                filtered.remove(dateStr)
            }
        }
        return filtered
    }

    func loadDatesWithData() async {
        do {
            // Fetch all points across a wide range (past 30 days + 14 day forecast)
            let siteIDs = sites.map { $0.id }
            guard !siteIDs.isEmpty else { datesWithData = []; return }
            let from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let to   = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
            let points = try await forecastRepository.fetchPoints(pvSiteIDs: siteIDs, from: from, to: to)
            var cal = Calendar.current; cal.timeZone = .current
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
            let dates = Set(points.map { fmt.string(from: $0.periodStart) })
            await MainActor.run { datesWithData = dates }
        } catch {
            // Non-critical to the user experience, but still logged.
            AppLogger.shared.error("DashboardViewModel: failed to load dates with data: \(error)")
        }
    }

    func loadQuota() async {
        do {
            let config = FetchTriggerConfigurationStore.load()
            // Pass location so nextAutoFetchTime/nextAutoRefreshTime can be computed
            let loc = try? await locationRepository.fetchCurrent()
            quotaStats = try await manageQuotaUseCase.globalStats(
                fetchTriggerConfig: config, location: loc)
        } catch {
            // Non-critical to the user experience (quota card just stays
            // empty), but still logged.
            AppLogger.shared.error("DashboardViewModel: failed to load quota stats: \(error)")
        }
    }

    func goToToday() async {
        let cal = Calendar.current
        selectedDate = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        selectedScenario = .normal; await loadAll()
    }

    func changeDate(_ newDate: Date) async {
        // Normalize to noon so Solar library resolves the correct day's sun window
        // (midnight dates can resolve to previous day's sunset)
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: newDate) ?? newDate
        selectedDate = noon; await loadAll()
    }

    func changeScenario(_ scenario: Scenario) async {
        selectedScenario = scenario; await loadAll()
    }

    func toggleSeriesVisibility(_ seriesID: String) {
        if hiddenSeriesIDs.contains(seriesID) { hiddenSeriesIDs.remove(seriesID) }
        else { hiddenSeriesIDs.insert(seriesID) }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true; errorMessage = nil
        defer { isRefreshing = false }
        do {
            try await fetchForecastUseCase.executeManual()
            await loadAll()
            // A manual call genuinely changes remaining quota for the rest
            // of the day — AutoRefreshIntervalCalculator no longer sets
            // aside a fixed reserve for manual use, so the auto-refresh
            // interval must be recomputed (loadAll()'s own loadQuota()
            // call already does this) AND the background job actually
            // resubmitted to reflect it, not just the in-memory UI state.
            let config = FetchTriggerConfigurationStore.load()
            if let loc = try? await locationRepository.fetchCurrent() {
                await DIContainer.shared.makeBGTaskCoordinator().scheduleNext(config: config, location: loc)
                await MainActor.run {
                    NotificationCenter.default.post(name: .quotaAffectingRescheduleOccurred, object: nil)
                }
            }
        } catch {
            let message = error.humanReadableMessage
            AppLogger.shared.error("Fetch failed: \(message)")
            errorMessage = message
            // The fetch itself failed (e.g. every site's call hit a real
            // 429 and executeManual() threw, or a single-site setup's
            // one and only call failed) — but the actual quota mutation
            // (recordUsage, and for a 429 specifically,
            // QuotaManager.forceQuotaExhausted) already happened INSIDE
            // execute() before that throw, so the card's displayed quota
            // is now genuinely stale relative to what actually just got
            // recorded. Reload it here too, on the failure path, not
            // just the success path above — otherwise a fully-failed
            // manual refresh (which is exactly the realistic 429
            // scenario) would never update the card at all.
            await loadQuota()
        }
    }

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    var datesWithData: Set<String> = []  // "yyyy-MM-dd" strings

    /// True when no sites or API keys are configured yet.
    var isUnconfigured: Bool { sites.isEmpty }

    /// True when configured but no forecast data exists for the selected date.
    var hasNoData: Bool { !isUnconfigured && chartSeries.allSatisfy { $0.points.isEmpty } }

    /// True when there is data available on a date after the selected date.
    var hasNextData: Bool {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
        let current = fmt.string(from: selectedDate)
        return datesWithData.contains { $0 > current }
    }

    /// True when there is data available on a date before the selected date.
    /// Site IDs whose API key is disabled — these should be toggled off in chart
    /// Sites that are assigned to an enabled API key — only these render in chart/breakdown
    var activeSites: [PVSite] {
        let enabledKeyIDs = Set(apiKeys.filter { $0.isEnabled }.map { $0.id })
        return sites.filter { site in
            guard let keyID = site.apiKeyID else { return false }
            return enabledKeyIDs.contains(keyID)
        }
    }

    var disabledSiteIDs: Set<String> {
        let disabledKeyIDs = Set(apiKeys.filter { !$0.isEnabled }.map { $0.id })
        return Set(sites.filter { disabledKeyIDs.contains($0.apiKeyID ?? UUID()) }
            .map { $0.id.uuidString })
    }

    var hasPreviousData: Bool {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
        let current = fmt.string(from: selectedDate)
        return datesWithData.contains { $0 < current }
    }
}
