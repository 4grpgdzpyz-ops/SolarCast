import Foundation
enum APIKeyMapper {
    static func toDomain(_ e: APIKeyEntity) -> APIKey {
        APIKey(id: e.id, name: e.name, keyValue: e.keyValue, isEnabled: e.isEnabled,
               dailyQuotaLimit: e.dailyQuotaLimit, reservedQuota: e.reservedQuota,
               assignedSiteIDs: (e.sites ?? []).map { $0.id })
    }
    static func apply(_ k: APIKey, to e: APIKeyEntity) {
        e.name = k.name; e.keyValue = k.keyValue; e.isEnabled = k.isEnabled
        e.dailyQuotaLimit = k.dailyQuotaLimit; e.reservedQuota = k.reservedQuota
    }
}
