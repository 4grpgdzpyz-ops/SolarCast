import Foundation
protocol PVSiteRepository: Sendable {
    func fetchAll() async throws -> [PVSite]
    func fetch(id: UUID) async throws -> PVSite?
    func save(_ site: PVSite) async throws
    func delete(id: UUID) async throws
}
