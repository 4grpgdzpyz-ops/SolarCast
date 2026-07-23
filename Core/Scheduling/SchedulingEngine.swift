import Foundation

/// Central scheduling authority with three responsibilities:
///
/// 1. nextScheduledFetch(): the single next thing that should wake the app
///    in the background — either the once-daily auto-fetch trigger, or
///    whichever enabled API key's own auto-refresh interval comes soonest.
///    Returns a ScheduledTrigger (not just a Date) so the caller
///    (BGTaskCoordinator) knows WHICH key (if any) actually won, needed to
///    restrict background execution to just that key's sites.
///
/// 2. staleAPIKeys(): used at app launch / foreground resume to decide
///    which keys need an immediate catch-up fetch, delegating the actual
///    per-key staleness rules to StalenessEvaluator.
///
/// 3. Owns the StalenessEvaluator instance internally, constructed from
///    the same repositories passed into this actor's own init.
actor SchedulingEngine {
    private let sunWindowCalculator: SunWindowCalculator
    private let sunriseScheduler: SunriseRelativeScheduler
    private let stalenessEvaluator: StalenessEvaluator
    private let apiKeyRepository: APIKeyRepository
    private let pvSiteRepository: PVSiteRepository
    private let quotaWindowTracker: QuotaWindowTracker

    /// The stable, remembered target for a key's next INSIDE-window
    /// refresh, plus the real usedToday value that produced it. Without
    /// this, computeNextRefresh's inside-window branch was a pure
    /// function of `now` — every real call (a Settings visit, a
    /// staleness check, anything that triggers scheduleNext again)
    /// recomputed a fresh "now + interval" from THAT call's own, later
    /// now, causing the actual target to visibly drift later and later
    /// on every re-trigger, even when nothing about quota usage had
    /// genuinely changed at all. Now the target is only recomputed when
    /// usedToday has actually, measurably changed since the last real
    /// computation for that key — otherwise the SAME, stable target is
    /// reused, which is what lets a reschedule genuinely recognize "this
    /// is still the same schedule" instead of always seeing a "new" time.
    private struct StableTarget {
        let usedToday: Int
        let date: Date
        let intervalMinutes: Int
    }
    private var stableTargets: [UUID: StableTarget] = [:]

    init(sunWindowCalculator: SunWindowCalculator,
         forecastRepository: ForecastRepository, quotaRepository: QuotaRepository,
         pvSiteRepository: PVSiteRepository, apiKeyRepository: APIKeyRepository,
         sunriseScheduler: SunriseRelativeScheduler = SunriseRelativeScheduler()) {
        self.sunWindowCalculator = sunWindowCalculator; self.sunriseScheduler = sunriseScheduler
        self.pvSiteRepository = pvSiteRepository
        self.apiKeyRepository = apiKeyRepository
        self.quotaWindowTracker = QuotaWindowTracker(quotaRepository: quotaRepository)
        self.stalenessEvaluator = StalenessEvaluator(
            forecastRepository: forecastRepository, quotaRepository: quotaRepository,
            pvSiteRepository: pvSiteRepository, sunWindowCalculator: sunWindowCalculator)
    }
    /// What triggered the next scheduled background task. Auto-fetch is a
    /// global, once-daily, all-sites event (no associated key); auto-refresh
    /// is per-key, so restricting execution to just that key's sites is
    /// possible once we know which key won. logCleanup has no key at all —
    /// it's independent of both PV data and daylight, driven purely by
    /// AppLogger's own UTC-midnight boundary.
    enum ScheduledTrigger {
        case fetch(Date)
        case refresh(Date, apiKeyID: UUID)
        case logCleanup(Date)

        var date: Date {
            switch self {
            case .fetch(let d): return d
            case .refresh(let d, _): return d
            case .logCleanup(let d): return d
            }
        }
    }

    func nextScheduledFetch(config: FetchTriggerConfiguration, location: UserLocation, now: Date = Date()) async -> ScheduledTrigger? {
        var candidates: [ScheduledTrigger] = []

        // Daily maintenance (quota-usage cleanup always; log cleanup
        // only if logging is enabled — decided inside the real handler,
        // not here) is genuinely independent of sun windows/location —
        // resolving today's sun window (needed below for fetch/refresh)
        // must NOT block this candidate from being considered. Always
        // scheduled regardless of the logging toggle — previously this
        // candidate only existed when logging was enabled, which meant
        // ANY cleanup work riding along with it (like quota-usage
        // cleanup) would silently never run at all for a user who had
        // disabled logging, a real, genuine bug for a feature that has
        // nothing conceptually to do with logging.
        let t = AppLogger.shared.nextCleanupBoundary(now: now)
        AppLogger.shared.info("SchedulingEngine: daily maintenance candidate at \(t)")
        candidates.append(.logCleanup(t))

        guard let todayWindow = await sunWindowCalculator.resolve(date: now, location: location) else {
            AppLogger.shared.error("SchedulingEngine: could not resolve today's sun window for \(location.name) — fetch/refresh candidates unavailable this cycle")
            return Self.pickWinner(candidates)
        }
        if config.autoFetchEnabled {
            switch config.autoFetchTiming {
            case .fixedTime(let h, let m):
                if let t = Self.nextOccurrence(hour: h, minute: m, after: now) {
                    AppLogger.shared.info("SchedulingEngine: auto-fetch candidate (fixed \(h):\(String(format: "%02d", m))) at \(t)")
                    candidates.append(.fetch(t))
                }
            case .sunriseRelative(let offset):
                let t = sunriseScheduler.resolveTriggerTime(sunWindow: todayWindow, offsetMinutes: offset)
                if t > now {
                    AppLogger.shared.info("SchedulingEngine: auto-fetch candidate (sunrise\(offset >= 0 ? "+" : "")\(offset)min, today) at \(t)")
                    candidates.append(.fetch(t))
                }
                else if let tmr = await sunWindowCalculator.resolve(date: now.addingTimeInterval(86400), location: location) {
                    let tmrTrigger = sunriseScheduler.resolveTriggerTime(sunWindow: tmr, offsetMinutes: offset)
                    AppLogger.shared.info("SchedulingEngine: auto-fetch candidate (sunrise\(offset >= 0 ? "+" : "")\(offset)min, tomorrow — today's already passed) at \(tmrTrigger)")
                    candidates.append(.fetch(tmrTrigger))
                }
            }
        }
        if config.autoRefreshEnabled {
            let allKeys = (try? await apiKeyRepository.fetchAll()) ?? []
            let keys = allKeys.filter(\.isEnabled)
            let sites = (try? await pvSiteRepository.fetchAll()) ?? []
            // Self-pruning for stableTargets — genuinely deleted keys
            // (not just disabled ones, which correctly keep their cached
            // entry) are dropped here, using the FULL, real, current key
            // list already being fetched for this same real cycle. No
            // new coupling to a "key was deleted" event anywhere else in
            // the app — this closes the gap opportunistically, on the
            // next real scheduling pass, which is frequent enough in
            // practice that "eventually, not instantly" is genuinely
            // sufficient for what was already a negligible, real risk.
            let realKeyIDs = Set(allKeys.map(\.id))
            stableTargets = stableTargets.filter { realKeyIDs.contains($0.key) }
            for key in keys {
                let assignedCount = sites.filter { $0.apiKeyID == key.id }.count
                if let result = await computeNextRefresh(key: key, assignedCount: assignedCount, config: config, location: location, now: now) {
                    AppLogger.shared.info("SchedulingEngine: auto-refresh candidate for key '\(key.name)' at \(result.date) (interval=\(result.intervalMinutes)min)")
                    candidates.append(.refresh(result.date, apiKeyID: key.id))
                } else {
                    AppLogger.shared.info("SchedulingEngine: key '\(key.name)' produced no refresh candidate (no computable interval)")
                }
            }
        }
        return Self.pickWinner(candidates)
    }

    /// Shared by both the normal end-of-function path and the early
    /// sun-window-resolution-failure path (which still needs to pick a
    /// winner from whatever candidates it has — just log cleanup, in that
    /// case — rather than discard everything).
    /// Computes a refresh candidate against TOMORROW's sun window, for
    /// when today's usable window is already exhausted (computeIntervalMinutes
    /// returned nil because remainingHours had dropped to 0 or too low to
    /// fit even one more refresh). Assumes a fresh quota day — the full
    /// dailyQuotaLimit, not usedToday-adjusted — since tomorrow's quota
    /// genuinely hasn't been touched yet (Solcast's quota resets at UTC
    /// midnight, confirmed elsewhere in this codebase, and
    /// usedSinceUTCMidnight now genuinely tracks by real calendar day,
    /// not an approximation). The reservation is recomputed against
    /// TOMORROW's own auto-fetch time (not today's), since tomorrow's
    /// fetch — if enabled — will also consume quota before any refresh
    /// happens that day.
    /// Computes the next auto-refresh time for a single key, per the
    /// exact three-step algorithm:
    ///
    /// STEP 1 — Determine whether `now` is inside or outside today's sun
    /// window. This is the real, top-level branch (via
    /// todayWindow.contains(now)), not "try today's formula and see if
    /// it fails."
    ///
    /// STEP 2 — INSIDE the window: available calls = (remaining quota -
    /// reserved) / assigned sites. interval = (time remaining to sunset)
    /// / (available calls + 1), rounded up to the nearest 10 minutes,
    /// floored at 15min. Next refresh = now + interval.
    ///
    /// STEP 3 — OUTSIDE the window (or the inside-window candidate would
    /// exceed sunset): available calls = (tomorrow's quota - reserved
    /// for tomorrow's auto-fetch if enabled) / assigned sites. The sun
    /// window used is ADJUSTED by the signed difference between
    /// tomorrow's auto-fetch time and tomorrow's own sunrise — added if
    /// fetch is before sunrise (extra lead time), subtracted if after
    /// (time already spent) — verified against a real worked example:
    /// fetch 05:30, sunrise 06:00 -> +30min -> 15.5h adjusted window.
    /// interval = adjustedWindow / (available calls + 1), same rounding.
    /// Next refresh = auto-fetch time + interval (if enabled) or sunrise
    /// + interval (if disabled).
    private func computeNextRefresh(key: APIKey, assignedCount: Int, config: FetchTriggerConfiguration,
                                    location: UserLocation, now: Date) async -> (date: Date, intervalMinutes: Int)? {
        guard let todayWindow = await sunWindowCalculator.resolve(date: now, location: location) else {
            return nil
        }
        if todayWindow.contains(now) {
            // STEP 2 — INSIDE the window.
            let usedToday = (try? await quotaWindowTracker.usedSinceUTCMidnight(apiKeyID: key.id, now: now)) ?? 0
            // Reuse the stable, remembered target if usedToday hasn't
            // genuinely changed since it was last computed for this key,
            // AND that target hasn't already elapsed (a persisted target
            // in the past is never valid to reuse, even if usedToday
            // still matches — the OS may simply not have run the job yet,
            // but a fresh computation is still needed once it's overdue).
            if let cached = stableTargets[key.id], cached.usedToday == usedToday, cached.date > now {
                return (cached.date, cached.intervalMinutes)
            }
            let remainingQuota = max(key.dailyQuotaLimit - usedToday, 0)
            let nextAutoFetch = await nextAutoFetchTime(config: config, location: location, now: now)
            let reserved = QuotaReservationPolicy.computeReservedQuota(
                dailyQuotaLimit: key.dailyQuotaLimit, nextAutoFetchDate: nextAutoFetch,
                assignedSiteCount: assignedCount, now: now)
            let remainingHours = max(todayWindow.sunset.timeIntervalSince(now) / 3600, 0)
            // The unlimited-quota check must use key.dailyQuotaLimit (the
            // real, original limit) — NOT remainingQuota, which correctly
            // becomes 0 once a LIMITED key's budget is genuinely
            // exhausted, but is numerically identical to
            // APIKey.unlimitedQuota's own sentinel (also 0). Passing
            // remainingQuota straight into computeIntervalMinutes would
            // silently misidentify "exhausted" as "unlimited," returning
            // the flat 60min fallback instead of correctly falling
            // through to Step 3.
            // The unlimited-quota check must use key.dailyQuotaLimit (the
            // real, original limit) — NOT remainingQuota, which correctly
            // becomes 0 once a LIMITED key's budget is genuinely
            // exhausted, but is numerically identical to
            // APIKey.unlimitedQuota's own sentinel (also 0), and
            // computeIntervalMinutes has no way to tell these apart once
            // it only sees a bare Int. So this branches explicitly
            // BEFORE ever calling it: a genuinely unlimited key always
            // gets the flat interval; a genuinely limited, exhausted key
            // (remainingQuota == 0) skips straight to Step 3 instead of
            // passing an ambiguous 0 through.
            let isGenuinelyUnlimited = key.dailyQuotaLimit == APIKey.unlimitedQuota
            var stepTwoResult: (date: Date, intervalMinutes: Int)?
            if isGenuinelyUnlimited {
                let interval = AutoRefreshIntervalCalculator.unlimitedQuotaIntervalMinutes
                let candidate = now.addingTimeInterval(TimeInterval(interval * 60))
                if candidate <= todayWindow.sunset {
                    stepTwoResult = (candidate, interval)
                }
                // Falls through to Step 3 — candidate would exceed sunset.
            } else if remainingQuota > 0,
                      let interval = AutoRefreshIntervalCalculator.computeIntervalMinutes(
                        dailyQuotaLimit: remainingQuota, autoFetchReservedCalls: reserved,
                        sunWindowHours: remainingHours, assignedSiteCount: assignedCount) {
                let candidate = now.addingTimeInterval(TimeInterval(interval * 60))
                if candidate <= todayWindow.sunset {
                    stepTwoResult = (candidate, interval)
                }
                // Falls through to Step 3 — candidate would exceed sunset,
                // or no interval could be computed at all.
            }
            // remainingQuota == 0 (genuinely exhausted, limited key)
            // falls straight through to Step 3 here, without ever
            // reaching computeIntervalMinutes with an ambiguous 0.
            if let stepTwoResult {
                stableTargets[key.id] = StableTarget(usedToday: usedToday, date: stepTwoResult.date, intervalMinutes: stepTwoResult.intervalMinutes)
                return stepTwoResult
            }
        }
        // STEP 3 — OUTSIDE the window (or fallen through from inside).
        let tomorrow = now.addingTimeInterval(86400)
        guard let tomorrowWindow = await sunWindowCalculator.resolve(date: tomorrow, location: location) else {
            return nil
        }
        let tomorrowFetch: Date? = {
            guard config.autoFetchEnabled else { return nil }
            switch config.autoFetchTiming {
            case .fixedTime(let h, let m):
                // Not Self.nextOccurrence(after: tomorrow) — that
                // searches for the next occurrence relative to its
                // reference date's own time-of-day, which cascades to
                // the wrong day whenever h:m is earlier than tomorrow's
                // current time-of-day. tomorrow already IS the target
                // date, so this just needs that date's own h:m, built
                // directly from its components.
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = h; comps.minute = m; comps.second = 0
                return Calendar.current.date(from: comps)
            case .sunriseRelative(let offset):
                return sunriseScheduler.resolveTriggerTime(sunWindow: tomorrowWindow, offsetMinutes: offset)
            }
        }()
        let reserved = QuotaReservationPolicy.computeReservedQuota(
            dailyQuotaLimit: key.dailyQuotaLimit, nextAutoFetchDate: tomorrowFetch,
            assignedSiteCount: assignedCount, now: tomorrow)
        // diff = sunrise - fetchTime — positive when fetch is BEFORE
        // sunrise (extra lead time, window grows), negative when AFTER
        // (time already spent, window shrinks). Added to the RAW window.
        let diffHours = tomorrowFetch.map { tomorrowWindow.sunrise.timeIntervalSince($0) / 3600 } ?? 0
        let rawWindowHours = tomorrowWindow.sunset.timeIntervalSince(tomorrowWindow.sunrise) / 3600
        let adjustedWindowHours = max(rawWindowHours + diffHours, 0)
        guard let interval = AutoRefreshIntervalCalculator.computeIntervalMinutes(
            dailyQuotaLimit: key.dailyQuotaLimit, autoFetchReservedCalls: reserved,
            sunWindowHours: adjustedWindowHours, assignedSiteCount: assignedCount) else {
            return nil
        }
        let anchor = tomorrowFetch ?? tomorrowWindow.sunrise
        let next = anchor.addingTimeInterval(TimeInterval(interval * 60))
        return next <= tomorrowWindow.sunset ? (next, interval) : nil
    }

    private static func pickWinner(_ candidates: [ScheduledTrigger]) -> ScheduledTrigger? {
        let winner = candidates.min(by: { $0.date < $1.date })
        if let winner {
            switch winner {
            case .fetch(let d):
                AppLogger.shared.info("SchedulingEngine: nextScheduledFetch winner = auto-fetch at \(d)")
            case .refresh(let d, let keyID):
                AppLogger.shared.info("SchedulingEngine: nextScheduledFetch winner = auto-refresh for key \(keyID) at \(d)")
            case .logCleanup(let d):
                AppLogger.shared.info("SchedulingEngine: nextScheduledFetch winner = log cleanup at \(d)")
            }
        } else {
            AppLogger.shared.info("SchedulingEngine: nextScheduledFetch produced no candidates at all (auto-fetch, auto-refresh, and logging are all disabled, or none produced a valid trigger)")
        }
        return winner
    }
    /// IDs of every enabled API key that is currently stale, per the rules
    /// in StalenessEvaluator (sun-window gated, per-key thresholds). An
    /// empty result means nothing needs fetching right now.
    func staleAPIKeys(apiKeys: [APIKey], config: FetchTriggerConfiguration,
                       location: UserLocation, now: Date = Date()) async -> [UUID] {
        let nextAutoFetch = await nextAutoFetchTime(config: config, location: location, now: now)
        return await stalenessEvaluator.staleAPIKeys(
            apiKeys: apiKeys, autoRefreshEnabled: config.autoRefreshEnabled,
            nextAutoFetchDate: nextAutoFetch, location: location, now: now)
    }

    /// Returns only the next auto-fetch trigger time (sunrise-relative or fixed),
    /// independent of auto-refresh. Used by the Auto Fetch settings card.
    func nextAutoFetchTime(config: FetchTriggerConfiguration, location: UserLocation, now: Date = Date()) async -> Date? {
        guard config.autoFetchEnabled else { return nil }
        guard let todayWindow = await sunWindowCalculator.resolve(date: now, location: location) else { return nil }
        switch config.autoFetchTiming {
        case .fixedTime(let h, let m):
            return Self.nextOccurrence(hour: h, minute: m, after: now)
        case .sunriseRelative(let offset):
            let t = sunriseScheduler.resolveTriggerTime(sunWindow: todayWindow, offsetMinutes: offset)
            if t > now { return t }
            if let tmr = await sunWindowCalculator.resolve(date: now.addingTimeInterval(86400), location: location) {
                return sunriseScheduler.resolveTriggerTime(sunWindow: tmr, offsetMinutes: offset)
            }
            return nil
        }
    }

    /// Returns the next auto-refresh trigger time based on the computed interval,
    /// independent of auto-fetch. Used by the Auto Refresh settings card.
    func nextAutoRefreshTime(config: FetchTriggerConfiguration, location: UserLocation, apiKeyID: UUID,
                              dailyQuotaLimit: Int = 10, assignedSiteCount: Int = 1, now: Date = Date()) async -> (date: Date, intervalMinutes: Int)? {
        guard config.autoRefreshEnabled else { return nil }
        // Thin delegation to the single, unified algorithm used
        // everywhere else — no separately-maintained implementation
        // here. This IS the fix for a confirmed, real bug: two
        // independent implementations of the same algorithm (this
        // function's own inline logic, vs SchedulingEngine's auto-refresh
        // loop) could silently disagree, since nothing guaranteed they
        // stayed in sync.
        let key = APIKey(id: apiKeyID, name: "", keyValue: "", isEnabled: true,
                         dailyQuotaLimit: dailyQuotaLimit, reservedQuota: 0, assignedSiteIDs: [])
        return await computeNextRefresh(key: key, assignedCount: assignedSiteCount, config: config, location: location, now: now)
    }

    private static func nextOccurrence(hour: Int, minute: Int, after date: Date) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        guard let t = cal.date(from: comps) else { return nil }
        return t > date ? t : cal.date(byAdding: .day, value: 1, to: t)
    }
}
