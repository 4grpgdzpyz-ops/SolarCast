import Foundation
import SwiftData
@Model final class APIKeyEntity {
    @Attribute(.unique) var id: UUID
    var name: String; var keyValue: String; var isEnabled: Bool
    var dailyQuotaLimit: Int; var reservedQuota: Int; var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \PVSiteEntity.apiKey) var sites: [PVSiteEntity]?
    @Relationship(deleteRule: .cascade, inverse: \QuotaUsageEntity.apiKey) var usageEvents: [QuotaUsageEntity]?
    init(id: UUID, name: String, keyValue: String, isEnabled: Bool, dailyQuotaLimit: Int, reservedQuota: Int, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.keyValue = keyValue; self.isEnabled = isEnabled
        self.dailyQuotaLimit = dailyQuotaLimit; self.reservedQuota = reservedQuota; self.createdAt = createdAt
        self.sites = []; self.usageEvents = []
    }
}
