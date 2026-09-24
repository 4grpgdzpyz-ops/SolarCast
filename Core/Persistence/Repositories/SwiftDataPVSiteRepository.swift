import Foundation
import SwiftData
actor SwiftDataPVSiteRepository: PVSiteRepository {
    private let modelContainer: ModelContainer
    init(modelContainer: ModelContainer) { self.modelContainer = modelContainer }
    func fetchAll() async throws -> [PVSite] {
        do {
            return try ModelContext(modelContainer).fetch(FetchDescriptor<PVSiteEntity>(sortBy: [SortDescriptor<PVSiteEntity>(\.createdAt)])).map(PVSiteMapper.toDomain)
        } catch {
            AppLogger.shared.error("PVSiteRepository: fetchAll failed: \(error)")
            throw error
        }
    }
    func fetch(id: UUID) async throws -> PVSite? {
        do {
            return try ModelContext(modelContainer).fetch(FetchDescriptor<PVSiteEntity>(predicate: #Predicate { $0.id == id })).first.map(PVSiteMapper.toDomain)
        } catch {
            AppLogger.shared.error("PVSiteRepository: fetch(id: \(id)) failed: \(error)")
            throw error
        }
    }
    func save(_ site: PVSite) async throws {
        let ctx = ModelContext(modelContainer)
        var keyEntity: APIKeyEntity?
        if let kid = site.apiKeyID {
            keyEntity = try ctx.fetch(FetchDescriptor<APIKeyEntity>(predicate: #Predicate { $0.id == kid })).first
        }
        let sid = site.id
        let isNew: Bool
        if let e = try ctx.fetch(FetchDescriptor<PVSiteEntity>(predicate: #Predicate { $0.id == sid })).first {
            PVSiteMapper.apply(site, to: e, apiKeyEntity: keyEntity)
            isNew = false
        } else {
            ctx.insert(PVSiteEntity(id: site.id, solcastSiteID: site.solcastSiteID, name: site.name, colorHex: site.colorHex, apiKey: keyEntity))
            isNew = true
        }
        do {
            try ctx.save()
            AppLogger.shared.info("PVSiteRepository: \(isNew ? "created" : "updated") site '\(site.name)' (\(site.id))")
        } catch {
            AppLogger.shared.error("PVSiteRepository: failed to save site '\(site.name)' (\(site.id)): \(error)")
            throw error
        }
    }
    func delete(id: UUID) async throws {
        let ctx = ModelContext(modelContainer)
        guard let e = try ctx.fetch(FetchDescriptor<PVSiteEntity>(predicate: #Predicate { $0.id == id })).first else {
            AppLogger.shared.warn("PVSiteRepository: delete requested for missing site \(id)")
            return
        }
        ctx.delete(e)
        do {
            try ctx.save()
            AppLogger.shared.info("PVSiteRepository: deleted site \(id)")
        } catch {
            AppLogger.shared.error("PVSiteRepository: failed to delete site \(id): \(error)")
            throw error
        }
    }
}
