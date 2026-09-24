import Foundation

/// Determines which enabled API keys currently have stale data and should
/// be re-fetched. Replaces the old flat "90 minutes since last fetch" rule
/// with per-key, sun-window-gated conditions:
///
/// 1. Resolve the sun window once, globally, from the app's configured
///    location — sunrise/sunset don't depend on any individual API key.
///
/// 2. OUTSIDE the sun window: a key is stale only if at least one of its
///    assigned PV sites has zero stored forecast points for today. If every
///    assigned site already has some data, the key is left alone — no point
///    spending API calls outside daylight hours to refresh something that
///    won't change before sunrise anyway.
///
/// 3. INSIDE the sun window: a key is stale if the time since its last
///    successful pull (fetch, refresh, or manual — whichever was most
///    recent, no matter how long ago) exceeds a threshold. Auto-refresh is
///    a single app-wide setting (FetchTriggerConfiguration.autoRefreshEnabled),
///    not per-key — when it's on, the threshold is that specific key's own
///    computed refresh interval (varies with its quota and assigned site
///    count); when it's off, every key uses a flat 3-hour threshold.
///
/// A disabled key is skipped entirely — never evaluated, never fetched.
struct StalenessEvaluator: Sendable {
    /// Threshold used when auto-refresh is globally disabled — 3 hours.
    static let disabledAutoRefreshThreshold: TimeInterval = 3 * 60 * 60

    private let forecastRepository: ForecastRepository
    private let quotaRepository: QuotaRepository
    private let pvSiteRepository: PVSiteRepository
    private let sunWindowCalculator: SunWindowCalculator

    init(forecastRepository: ForecastRepository, quotaRepository: QuotaRepository,
         pvSiteRepository: PVSiteRepository, sunWindowCalculator: SunWindowCalculator) {
        self.forecastRepository = forecastRepository
        self.quotaRepository = quotaRepository
        self.pvSiteRepository = pvSiteRepository
        self.sunWindowCalculator = sunWindowCalculator
    }

    /// Returns the IDs of every enabled API key that is currently stale and
    /// should be fetched. An empty result means nothing needs fetching.
    func staleAPIKeys(apiKeys: [APIKey], autoRefreshEnabled: Bool, nextAutoFetchDate: Date?,
                       location: UserLocation, now: Date = Date()) async -> [UUID] {
        let enabledKeys = apiKeys.filter(\.isEnabled)
        guard !enabledKeys.isEmpty else { return [] }

        guard let sunWindow = await sunWindowCalculator.resolve(date: now, location: location) else {
            // No resolvable sun window (e.g. a location edge case) — can't
            // evaluate the daylight-dependent rules, so nothing is treated
            // as stale rather than guessing.
            return []
        }
        let insideSunWindow = sunWindow.contains(now)
        let allSites = (try? await pvSiteRepository.fetchAll()) ?? []
        AppLogger.shared.info(
            "Staleness check: \(enabledKeys.count) enabled key(s), insideSunWindow=\(insideSunWindow), autoRefreshEnabled=\(autoRefreshEnabled)")

        var staleKeyIDs: [UUID] = []
        for key in enabledKeys {
            let assignedSites = allSites.filter { $0.apiKeyID == key.id }
            let stale: Bool
            if insideSunWindow {
                stale = await isStaleWithinSunWindow(
                    key: key, assignedSiteCount: assignedSites.count,
                    autoRefreshEnabled: autoRefreshEnabled, nextAutoFetchDate: nextAutoFetchDate,
                    sunWindowHours: sunWindow.roundedHours, now: now)
            } else {
                stale = await isStaleOutsideSunWindow(assignedSites: assignedSites, now: now)
            }
            AppLogger.shared.info("Staleness check: key '\(key.name)' — \(stale ? "STALE, will fetch" : "fresh")")
            if stale { staleKeyIDs.append(key.id) }
        }
        return staleKeyIDs
    }

    // MARK: - Outside sun window: data-existence check

    private func isStaleOutsideSunWindow(assignedSites: [PVSite], now: Date) async -> Bool {
        guard !assignedSites.isEmpty else { return false }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now

        for site in assignedSites {
            let points = (try? await forecastRepository.fetchPoints(
                pvSiteIDs: [site.id], from: todayStart, to: todayEnd)) ?? []
            if points.isEmpty {
                // At least one assigned site has no data at all for today.
                return true
            }
        }
        return false
    }

    // MARK: - Inside sun window: elapsed-time-since-last-pull check

    private func isStaleWithinSunWindow(key: APIKey, assignedSiteCount: Int, autoRefreshEnabled: Bool,
                                        nextAutoFetchDate: Date?, sunWindowHours: Int, now: Date) async -> Bool {
        guard let lastPull = await lastSuccessfulPull(apiKeyID: key.id, now: now) else {
            return true // never pulled at all — stale
        }
        let elapsed = now.timeIntervalSince(lastPull)

        guard autoRefreshEnabled else {
            return elapsed > Self.disabledAutoRefreshThreshold
        }

        // Auto-refresh is on: use THIS key's own computed interval, the same
        // way SettingsViewModel derives it, so "stale" lines up with "when
        // this key's next scheduled refresh was actually supposed to fire"
        // rather than an unrelated number.
        let reserved = QuotaReservationPolicy.computeReservedQuota(
            dailyQuotaLimit: key.dailyQuotaLimit, nextAutoFetchDate: nextAutoFetchDate,
            assignedSiteCount: assignedSiteCount, now: now)
        guard let intervalMinutes = AutoRefreshIntervalCalculator.computeIntervalMinutes(
            dailyQuotaLimit: key.dailyQuotaLimit, autoFetchReservedCalls: reserved,
            sunWindowHours: Double(sunWindowHours), assignedSiteCount: assignedSiteCount) else {
            // No interval computable (e.g. no sites assigned to this key,
            // or its quota can't support any refreshes) — fall back to the
            // disabled threshold rather than never flagging it stale.
            return elapsed > Self.disabledAutoRefreshThreshold
        }
        return elapsed > TimeInterval(intervalMinutes * 60)
    }

    /// Most recent successful pull for a key across fetch, refresh, and
    /// manual purposes combined — whichever happened most recently, with no
    /// time-window restriction (unlike QuotaManager.currentStats, which
    /// only looks at the trailing 24h — staleness needs the true last pull,
    /// however long ago that was).
    private func lastSuccessfulPull(apiKeyID: UUID, now: Date) async -> Date? {
        let events = (try? await quotaRepository.fetchUsageEvents(
            apiKeyID: apiKeyID, from: .distantPast, to: now)) ?? []
        return events.filter(\.wasSuccessful).map(\.timestamp).max()
    }
}
