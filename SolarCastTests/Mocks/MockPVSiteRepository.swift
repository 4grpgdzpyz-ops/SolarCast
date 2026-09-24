import Foundation
@testable import SolarCast

actor MockPVSiteRepository: PVSiteRepository {
    var sites: [PVSite] = []
    func fetchAll() async throws -> [PVSite] { sites }
    func fetch(id: UUID) async throws -> PVSite? { sites.first { $0.id == id } }
    func save(_ site: PVSite) async throws {
        if let i = sites.firstIndex(where: { $0.id == site.id }) { sites[i] = site }
        else { sites.append(site) }
    }
    func delete(id: UUID) async throws { sites.removeAll { $0.id == id } }
}
