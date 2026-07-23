import Foundation
actor QuotaManager {
    private let quotaRepository: QuotaRepository
    private let windowTracker: QuotaWindowTracker
    init(quotaRepository: QuotaRepository) {
        self.quotaRepository = quotaRepository
        self.windowTracker = QuotaWindowTracker(quotaRepository: quotaRepository)
    }
    func canMakeCall(apiKey: APIKey, purpose: FetchPurpose, now: Date = Date()) async throws -> Bool {
        guard apiKey.isEnabled else { return false }
        guard !apiKey.hasUnlimitedQuota else { return true }
        let used = try await windowTracker.usedSinceUTCMidnight(apiKeyID: apiKey.id, now: now)
        guard used < apiKey.dailyQuotaLimit else { return false }
        switch purpose {
        case .autoFetch, .autoRefresh: return true
        case .manual, .appLaunchStaleness, .imported, .rateLimitCorrection: return apiKey.availableForManualUse(used: used) > 0
        }
    }
    func recordUsage(apiKeyID: UUID, wasSuccessful: Bool, purpose: FetchPurpose, isMock: Bool, consumedRealCall: Bool = true, now: Date = Date()) async throws {
        try await quotaRepository.recordUsage(
            QuotaUsageEvent(apiKeyID: apiKeyID, timestamp: now, wasSuccessful: wasSuccessful, purpose: purpose, isMock: isMock, consumedRealCall: consumedRealCall))
    }

    /// Forces a key's quota to fully consumed — used specifically when
    /// Solcast itself reports rate-limiting (HTTP 429), meaning the
    /// REAL, server-side count is genuinely already exhausted, whatever
    /// this app's own local event log currently shows. "Used quota" has
    /// no separate stored field anywhere in this app — it's always
    /// derived live from real QuotaUsageEvent history via
    /// usedSinceUTCMidnight — so the only real way to make that derived
    /// value land at dailyQuotaLimit immediately is inserting enough
    /// synthetic events to bring the current UTC day's count up to it.
    /// "Available quota" needs no separate action here —
    /// APIKey.availableForManualUse(used:) is itself a computed function
    /// that automatically floors at 0 once used reaches the limit, so
    /// setting used correctly satisfies that too.
    func forceQuotaExhausted(apiKey: APIKey, isMock: Bool, now: Date = Date()) async throws {
        guard !apiKey.hasUnlimitedQuota else {
            AppLogger.shared.info("QuotaManager: forceQuotaExhausted skipped for key '\(apiKey.name)' — unlimited quota, nothing to exhaust")
            return
        }
        let used = try await windowTracker.usedSinceUTCMidnight(apiKeyID: apiKey.id, now: now)
        // Explicitly clamped, not just "dailyQuotaLimit - used" taken at
        // face value — even though this function's own insert already
        // never overshoots within a single execution (used + deficit ==
        // dailyQuotaLimit exactly, by construction), a genuinely
        // concurrent write from elsewhere (a different real trigger
        // hitting this same key's exhaustion at the same instant) could
        // theoretically complete between this query and the insert
        // below. max(..., 0) ensures deficit itself can never go
        // negative, and the guard below still correctly skips entirely
        // once used has already reached or passed the real limit.
        let deficit = max(apiKey.dailyQuotaLimit - used, 0)
        guard deficit > 0 else {
            AppLogger.shared.info("QuotaManager: forceQuotaExhausted skipped for key '\(apiKey.name)' — already at or above limit (used=\(used), limit=\(apiKey.dailyQuotaLimit))")
            return
        }
        let correctionEvents = (0..<deficit).map { _ in
            // consumedRealCall: true is deliberate here, not just the
            // default — these synthetic events exist specifically to
            // bring the LOCAL count up to the REAL, already-exhausted
            // server-side state, so they genuinely need to count toward
            // usedSinceUTCMidnight's total, even though they aren't
            // literally individual API calls themselves.
            QuotaUsageEvent(apiKeyID: apiKey.id, timestamp: now, wasSuccessful: true, purpose: .rateLimitCorrection, isMock: isMock, consumedRealCall: true)
        }
        try await quotaRepository.recordUsage(correctionEvents)
        AppLogger.shared.info("QuotaManager: forceQuotaExhausted for key '\(apiKey.name)' — recorded \(deficit) synthetic event(s) to bring used quota to limit (\(apiKey.dailyQuotaLimit)) after a real HTTP 429")
    }
    func currentStats(apiKey: APIKey, assignedSiteNames: [String], nextAutoFetchTime: Date?, nextAutoRefreshTime: Date?,
                      nextAutoRefreshIntervalMinutes: Int?, now: Date = Date()) async throws -> QuotaStats {
        let keyName = apiKey.name
        let used = try await windowTracker.usedSinceUTCMidnight(apiKeyID: apiKey.id, now: now)
        let events = try await quotaRepository.fetchUsageEvents(apiKeyID: apiKey.id, from: now.addingTimeInterval(-86400), to: now)
        let successful = events.filter { $0.wasSuccessful }
        let lastFetch = successful.filter { [.autoFetch, .manual, .appLaunchStaleness].contains($0.purpose) }.map(\.timestamp).max()
        let lastRefresh = successful.filter { $0.purpose == .autoRefresh }.map(\.timestamp).max()
        return QuotaStats(apiKeyID: apiKey.id, keyName: keyName, limit: apiKey.dailyQuotaLimit, used: used,
                          reserved: apiKey.reservedQuota, assignedSiteNames: assignedSiteNames,
                          lastFetchTimestamp: lastFetch, lastRefreshTimestamp: lastRefresh,
                          nextAutoFetchTime: nextAutoFetchTime, nextAutoRefreshTime: nextAutoRefreshTime,
                          nextAutoRefreshIntervalMinutes: nextAutoRefreshIntervalMinutes,
                          isKeyEnabled: apiKey.isEnabled)
    }

    /// Deletes quota-usage history older than the last UTC midnight —
    /// the start of the CURRENT UTC day. Nothing in this app's real
    /// quota logic (usedSinceUTCMidnight) ever looks back further than
    /// that same boundary, so anything older is pure historical record
    /// with zero live computational relevance. Called from the daily
    /// maintenance job, unconditionally — unlike log cleanup, this does
    /// NOT depend on any user-facing toggle, since quota tracking is a
    /// real, core feature, not an optional diagnostic one.
    func cleanupOldQuotaUsage(now: Date = Date()) async {
        let cutoff = UTCCalendar.calendar.startOfDay(for: now)
        do {
            try await quotaRepository.deleteEvents(olderThan: cutoff)
        } catch {
            AppLogger.shared.error("QuotaManager: cleanupOldQuotaUsage failed: \(error)")
        }
    }
}
