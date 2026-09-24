import Foundation
import SwiftData
actor SwiftDataLocationRepository: LocationRepository {
    private let modelContainer: ModelContainer
    init(modelContainer: ModelContainer) { self.modelContainer = modelContainer }
    func fetchCurrent() async throws -> UserLocation? {
        do {
            return try ModelContext(modelContainer).fetch(FetchDescriptor<LocationEntity>()).first.map {
                UserLocation(id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
            }
        } catch {
            AppLogger.shared.error("LocationRepository: fetchCurrent failed: \(error)")
            throw error
        }
    }
    func delete() async throws {
        let ctx = ModelContext(modelContainer)
        let existing = try ctx.fetch(FetchDescriptor<LocationEntity>())
        for e in existing { ctx.delete(e) }
        do {
            try ctx.save()
            AppLogger.shared.info("LocationRepository: deleted \(existing.count) location entr(y/ies)")
        } catch {
            AppLogger.shared.error("LocationRepository: failed to delete location: \(error)")
            throw error
        }
    }

    func save(_ location: UserLocation) async throws {
        let ctx = ModelContext(modelContainer)
        for e in try ctx.fetch(FetchDescriptor<LocationEntity>()) { ctx.delete(e) }
        ctx.insert(LocationEntity(id: location.id, name: location.name,
                                  latitude: location.latitude, longitude: location.longitude))
        do {
            try ctx.save()
            AppLogger.shared.info("LocationRepository: saved location '\(location.name)'")
        } catch {
            AppLogger.shared.error("LocationRepository: failed to save location '\(location.name)': \(error)")
            throw error
        }
    }
}
