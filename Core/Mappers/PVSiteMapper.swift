import Foundation
enum PVSiteMapper {
    static func toDomain(_ e: PVSiteEntity) -> PVSite {
        PVSite(id: e.id, solcastSiteID: e.solcastSiteID, name: e.name, colorHex: e.colorHex, apiKeyID: e.apiKey?.id)
    }
    static func apply(_ s: PVSite, to e: PVSiteEntity, apiKeyEntity: APIKeyEntity?) {
        e.solcastSiteID = s.solcastSiteID; e.name = s.name; e.colorHex = s.colorHex; e.apiKey = apiKeyEntity
    }
}
