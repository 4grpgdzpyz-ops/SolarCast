import Foundation
import SwiftData
@Model final class PVSiteEntity {
    @Attribute(.unique) var id: UUID
    var solcastSiteID: String; var name: String; var colorHex: String; var createdAt: Date
    var apiKey: APIKeyEntity?
    @Relationship(deleteRule: .cascade, inverse: \ForecastPointEntity.pvSite) var forecastPoints: [ForecastPointEntity]?
    init(id: UUID, solcastSiteID: String, name: String, colorHex: String, apiKey: APIKeyEntity? = nil, createdAt: Date = Date()) {
        self.id = id; self.solcastSiteID = solcastSiteID; self.name = name
        self.colorHex = colorHex; self.apiKey = apiKey; self.createdAt = createdAt; self.forecastPoints = []
    }
}
