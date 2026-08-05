import Foundation
@testable import SolarCast

actor MockQuotaRepository: QuotaRepository {
    var events: [QuotaUsageEvent] = []
    /// Replaces all events outright — needed for tests with multiple
    /// sub-cases in one test function (e.g. "fresh" then "stale" scenarios
    /// for the same key), where recordUsage()'s append-only behavior can't
    /// reset prior state between sub-cases.
    func seedEvents(_ newEvents: [QuotaUsageEvent]) {
        events = newEvents
    }
    func recordUsage(_ event: QuotaUsageEvent) async throws { events.append(event) }
    func recordUsage(_ events newEvents: [QuotaUsageEvent]) async throws { events.append(contentsOf: newEvents) }
    func fetchUsageEvents(apiKeyID: UUID, from: Date, to: Date) async throws -> [QuotaUsageEvent] {
        events.filter { $0.apiKeyID == apiKeyID && $0.timestamp >= from && $0.timestamp <= to }
    }
    func deleteAllEvents(isMock: Bool) async throws {
        events.removeAll { $0.isMock == isMock }
    }
    func deleteEvents(olderThan cutoff: Date) async throws {
        events.removeAll { $0.timestamp < cutoff }
    }
}
