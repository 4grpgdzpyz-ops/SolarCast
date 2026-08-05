import Foundation
import SwiftData

actor SwiftDataForecastRepository: ForecastRepository {
    private let modelContainer: ModelContainer
    init(modelContainer: ModelContainer) { self.modelContainer = modelContainer }

    func upsert(points: [ForecastPoint]) async throws {
        guard !points.isEmpty else { return }
        let ctx = ModelContext(modelContainer)
        let bySite = Dictionary(grouping: points, by: { $0.pvSiteID })

        for (siteID, sitePoints) in bySite {
            let siteDesc = FetchDescriptor<PVSiteEntity>(
                predicate: #Predicate { $0.id == siteID })
            guard let siteEntity = try ctx.fetch(siteDesc).first else {
                AppLogger.shared.warn("No PVSiteEntity found for siteID \(siteID) — skipping upsert for \(sitePoints.count) points")
                continue
            }

            var existingByID: [String: ForecastPointEntity] = [:]
            for p in sitePoints {
                let pid = p.id
                let desc = FetchDescriptor<ForecastPointEntity>(
                    predicate: #Predicate { $0.pointID == pid })
                if let existing = try ctx.fetch(desc).first {
                    existingByID[pid] = existing
                }
            }
            for p in sitePoints {
                if let existing = existingByID[p.id] {
                    ForecastPointEntityMapper.apply(p, to: existing)
                } else {
                    ctx.insert(ForecastPointEntityMapper.makeEntity(from: p, pvSite: siteEntity))
                }
            }
        }
        do {
            try ctx.save()
            AppLogger.shared.info("ForecastRepository: upserted \(points.count) point(s) across \(bySite.count) site(s)")
        } catch {
            AppLogger.shared.error("ForecastRepository: failed to upsert \(points.count) point(s): \(error)")
            throw error
        }
    }

    func fetchPoints(pvSiteIDs: [UUID], from: Date, to: Date) async throws -> [ForecastPoint] {
        guard !pvSiteIDs.isEmpty else { return [] }
        let ctx = ModelContext(modelContainer)
        let siteIDSet = Set(pvSiteIDs)
        // Scope reads to the CURRENT mode — this is what actually makes it
        // safe to stop deleting data on mode switch (see reloadAPIClient):
        // both mock and real data can coexist in storage simultaneously,
        // with only the current mode's records ever displayed. Switching
        // modes now changes what's shown, not what's stored, so a user's
        // real data survives a mock excursion and reappears automatically
        // on switching back — matching what the Settings confirmation
        // dialog's own wording ("switch...instead of") already promised.
        let isMockMode = UserDefaults.standard.bool(forKey: "solarcast.useMockData")

        // Avoid optional chaining (pvSite!.id) inside #Predicate — throws SwiftData error 1.
        // Fetch by time range only (safe predicates), then filter by siteID in memory.
        let desc = FetchDescriptor<ForecastPointEntity>(
            predicate: #Predicate { entity in
                entity.periodStart >= from && entity.periodStart <= to && entity.isMock == isMockMode
            },
            sortBy: [SortDescriptor(\.periodStart)])

        // Only logs on failure, not every call — this is a high-frequency
        // read (every chart render, every stats computation), so logging
        // every success at .info would flood the log file without adding
        // real diagnostic value. A failure here is genuinely rare and
        // always worth knowing about.
        let entities: [ForecastPointEntity]
        do {
            entities = try ctx.fetch(desc)
        } catch {
            AppLogger.shared.error("ForecastRepository: fetchPoints failed for \(pvSiteIDs.count) site(s) in range \(from)...\(to): \(error)")
            throw error
        }
        return entities.compactMap { entity -> ForecastPoint? in
            guard let siteID = entity.pvSite?.id,
                  siteIDSet.contains(siteID) else { return nil }
            return ForecastPointEntityMapper.toDomain(entity)
        }
    }

    func deletePoints(matching ids: [String]) async throws {
        let ctx = ModelContext(modelContainer)
        var deletedCount = 0
        for pid in ids {
            let desc = FetchDescriptor<ForecastPointEntity>(
                predicate: #Predicate { $0.pointID == pid })
            if let entity = try ctx.fetch(desc).first {
                ctx.delete(entity)
                deletedCount += 1
            }
        }
        do {
            try ctx.save()
            AppLogger.shared.info("ForecastRepository: deleted \(deletedCount)/\(ids.count) matched point(s)")
        } catch {
            AppLogger.shared.error("ForecastRepository: failed to delete matched points: \(error)")
            throw error
        }
    }

    func deleteAllPoints(isMock: Bool) async throws {
        let ctx = ModelContext(modelContainer)
        let desc = FetchDescriptor<ForecastPointEntity>(
            predicate: #Predicate { $0.isMock == isMock })
        let matched = try ctx.fetch(desc)
        for e in matched { ctx.delete(e) }
        do {
            try ctx.save()
            AppLogger.shared.info("Purged \(matched.count) \(isMock ? "mock" : "real") forecast point(s)")
        } catch {
            AppLogger.shared.error("ForecastRepository: failed to purge \(isMock ? "mock" : "real") points: \(error)")
            throw error
        }
    }
}
