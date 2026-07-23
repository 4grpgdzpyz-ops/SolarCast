import Foundation
import SwiftData

actor SwiftDataQuotaRepository: QuotaRepository {
    private let modelContainer: ModelContainer
    init(modelContainer: ModelContainer) { self.modelContainer = modelContainer }

    func recordUsage(_ event: QuotaUsageEvent) async throws {
        let ctx = ModelContext(modelContainer)
        let kid = event.apiKeyID
        let keyEntity = try ctx.fetch(FetchDescriptor<APIKeyEntity>(
            predicate: #Predicate { $0.id == kid })).first
        ctx.insert(QuotaUsageEntity(
            id: event.id, apiKey: keyEntity, timestamp: event.timestamp,
            wasSuccessful: event.wasSuccessful, purposeRawValue: event.purpose.rawValue,
            isMock: event.isMock, consumedRealCall: event.consumedRealCall))
        do {
            try ctx.save()
            AppLogger.shared.info("QuotaRepository: recorded \(event.purpose.rawValue) usage for key \(event.apiKeyID) — success=\(event.wasSuccessful), isMock=\(event.isMock), consumedRealCall=\(event.consumedRealCall)")
        } catch {
            AppLogger.shared.error("QuotaRepository: failed to record usage for key \(event.apiKeyID): \(error)")
            throw error
        }
    }

    func recordUsage(_ events: [QuotaUsageEvent]) async throws {
        guard !events.isEmpty else { return }
        let ctx = ModelContext(modelContainer)
        // Real key-entity lookups are cached per apiKeyID, not repeated
        // once per event — every event in a real batch (e.g.
        // forceQuotaExhausted's corrections) shares the same apiKeyID.
        var keyEntityCache: [UUID: APIKeyEntity?] = [:]
        for event in events {
            let kid = event.apiKeyID
            if keyEntityCache[kid] == nil {
                keyEntityCache[kid] = try ctx.fetch(FetchDescriptor<APIKeyEntity>(
                    predicate: #Predicate { $0.id == kid })).first
            }
            ctx.insert(QuotaUsageEntity(
                id: event.id, apiKey: keyEntityCache[kid] ?? nil, timestamp: event.timestamp,
                wasSuccessful: event.wasSuccessful, purposeRawValue: event.purpose.rawValue,
                isMock: event.isMock, consumedRealCall: event.consumedRealCall))
        }
        do {
            try ctx.save()
            AppLogger.shared.info("QuotaRepository: recorded \(events.count) \(events[0].purpose.rawValue) usage event(s) for key \(events[0].apiKeyID) in one batch — isMock=\(events[0].isMock), consumedRealCall=\(events[0].consumedRealCall)")
        } catch {
            AppLogger.shared.error("QuotaRepository: failed to record \(events.count) batched usage event(s): \(error)")
            throw error
        }
    }

    func fetchUsageEvents(apiKeyID: UUID, from: Date, to: Date) async throws -> [QuotaUsageEvent] {
        let ctx = ModelContext(modelContainer)
        // Scoped to the CURRENT mode — same reasoning as
        // SwiftDataForecastRepository.fetchPoints: mock and real quota
        // events coexist in storage, and only the current mode's events
        // are ever returned here. Mock events are explicitly purged on
        // disabling mock mode (see deleteAllEvents, called from
        // DIContainer.reloadAPIClient) — this filter is what keeps them
        // from showing up WHILE mock is still active, not a substitute for
        // deleting them once it's turned off.
        let isMockMode = UserDefaults.standard.bool(forKey: "solarcast.useMockData")
        // Avoid optional chaining ($0.apiKey!.id) inside #Predicate — unreliable in SwiftData.
        // Fetch by time window only, then filter by apiKeyID in memory.
        let desc = FetchDescriptor<QuotaUsageEntity>(
            predicate: #Predicate { $0.timestamp >= from && $0.timestamp <= to && $0.isMock == isMockMode },
            sortBy: [SortDescriptor(\.timestamp)])
        let entities: [QuotaUsageEntity]
        do {
            entities = try ctx.fetch(desc)
        } catch {
            AppLogger.shared.error("QuotaRepository: fetchUsageEvents failed for key \(apiKeyID): \(error)")
            throw error
        }
        return entities.compactMap { e -> QuotaUsageEvent? in
            guard e.apiKey?.id == apiKeyID,
                  let purpose = FetchPurpose(rawValue: e.purposeRawValue) else { return nil }
            return QuotaUsageEvent(id: e.id, apiKeyID: apiKeyID, timestamp: e.timestamp,
                                   wasSuccessful: e.wasSuccessful, purpose: purpose, isMock: e.isMock,
                                   consumedRealCall: e.consumedRealCall)
        }
    }

    func deleteAllEvents(isMock: Bool) async throws {
        let ctx = ModelContext(modelContainer)
        let desc = FetchDescriptor<QuotaUsageEntity>(
            predicate: #Predicate { $0.isMock == isMock })
        let matched = try ctx.fetch(desc)
        for e in matched { ctx.delete(e) }
        do {
            try ctx.save()
            AppLogger.shared.info("Purged \(matched.count) \(isMock ? "mock" : "real") quota usage event(s)")
        } catch {
            AppLogger.shared.error("QuotaRepository: failed to purge \(isMock ? "mock" : "real") events: \(error)")
            throw error
        }
    }

    func deleteEvents(olderThan cutoff: Date) async throws {
        let ctx = ModelContext(modelContainer)
        let desc = FetchDescriptor<QuotaUsageEntity>(
            predicate: #Predicate { $0.timestamp < cutoff })
        let matched = try ctx.fetch(desc)
        for e in matched { ctx.delete(e) }
        do {
            try ctx.save()
            AppLogger.shared.info("QuotaRepository: purged \(matched.count) quota usage event(s) older than \(cutoff)")
        } catch {
            AppLogger.shared.error("QuotaRepository: failed to purge events older than \(cutoff): \(error)")
            throw error
        }
    }
}
