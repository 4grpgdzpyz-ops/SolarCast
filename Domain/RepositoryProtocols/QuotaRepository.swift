import Foundation
protocol QuotaRepository: Sendable {
    func recordUsage(_ event: QuotaUsageEvent) async throws
    /// Records multiple events as a single, real batch — one
    /// ModelContext, one save(), not N separate transactions. Used
    /// specifically for QuotaManager.forceQuotaExhausted's synthetic
    /// correction events, which previously called the single-event
    /// recordUsage(_:) once per event, meaning N separate database
    /// writes AND N separate log lines for what is genuinely one real
    /// occurrence (a single 429 forcing a key to exhausted).
    func recordUsage(_ events: [QuotaUsageEvent]) async throws
    func fetchUsageEvents(apiKeyID: UUID, from: Date, to: Date) async throws -> [QuotaUsageEvent]
    /// Deletes every stored usage event whose isMock flag matches the given
    /// value. Mirrors ForecastRepository.deleteAllPoints(isMock:) — used
    /// when the mock/real toggle changes, so mock-mode quota events don't
    /// linger indefinitely once mock mode is disabled.
    func deleteAllEvents(isMock: Bool) async throws
    /// Deletes every stored usage event with a timestamp strictly before
    /// the given cutoff date. Used by the daily maintenance job to clean
    /// up quota-usage history older than the last UTC midnight — nothing
    /// in this app's real quota logic (usedSinceUTCMidnight) ever looks
    /// back further than the current UTC day, so older events are pure
    /// historical record with no live computational relevance, and would
    /// otherwise accumulate indefinitely.
    func deleteEvents(olderThan cutoff: Date) async throws
}
