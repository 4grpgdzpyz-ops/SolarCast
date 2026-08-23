import Foundation
import SwiftData
actor SwiftDataAPIKeyRepository: APIKeyRepository {
    private let modelContainer: ModelContainer
    init(modelContainer: ModelContainer) { self.modelContainer = modelContainer }
    func fetchAll() async throws -> [APIKey] {
        do {
            return try ModelContext(modelContainer).fetch(FetchDescriptor<APIKeyEntity>(sortBy: [SortDescriptor<APIKeyEntity>(\.createdAt)])).map(APIKeyMapper.toDomain)
        } catch {
            AppLogger.shared.error("APIKeyRepository: fetchAll failed: \(error)")
            throw error
        }
    }
    func fetch(id: UUID) async throws -> APIKey? {
        do {
            return try ModelContext(modelContainer).fetch(FetchDescriptor<APIKeyEntity>(predicate: #Predicate { $0.id == id })).first.map(APIKeyMapper.toDomain)
        } catch {
            AppLogger.shared.error("APIKeyRepository: fetch(id: \(id)) failed: \(error)")
            throw error
        }
    }
    func save(_ key: APIKey) async throws {
        let ctx = ModelContext(modelContainer); let kid = key.id
        let isNew: Bool
        if let e = try ctx.fetch(FetchDescriptor<APIKeyEntity>(predicate: #Predicate { $0.id == kid })).first {
            APIKeyMapper.apply(key, to: e)
            isNew = false
        } else {
            ctx.insert(APIKeyEntity(id: key.id, name: key.name, keyValue: key.keyValue, isEnabled: key.isEnabled,
                                    dailyQuotaLimit: key.dailyQuotaLimit, reservedQuota: key.reservedQuota))
            isNew = true
        }
        do {
            try ctx.save()
            AppLogger.shared.info("APIKeyRepository: \(isNew ? "created" : "updated") key '\(key.name)' (\(key.id))")
        } catch {
            AppLogger.shared.error("APIKeyRepository: failed to save key '\(key.name)' (\(key.id)): \(error)")
            throw error
        }
    }
    func delete(id: UUID) async throws {
        let ctx = ModelContext(modelContainer)
        guard let e = try ctx.fetch(FetchDescriptor<APIKeyEntity>(predicate: #Predicate { $0.id == id })).first else {
            AppLogger.shared.warn("APIKeyRepository: delete requested for missing key \(id)")
            return
        }
        ctx.delete(e)
        do {
            try ctx.save()
            AppLogger.shared.info("APIKeyRepository: deleted key \(id)")
        } catch {
            AppLogger.shared.error("APIKeyRepository: failed to delete key \(id): \(error)")
            throw error
        }
    }
}
