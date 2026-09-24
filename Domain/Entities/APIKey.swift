import Foundation
struct APIKey: Identifiable, Equatable, Sendable {
    static let defaultDailyQuotaLimit = 10
    static let unlimitedQuota = 0
    let id: UUID
    var name: String
    var keyValue: String
    var isEnabled: Bool
    var dailyQuotaLimit: Int
    var reservedQuota: Int
    var assignedSiteIDs: [UUID]
    var createdAt: Date?
    init(id: UUID = UUID(), name: String, keyValue: String, isEnabled: Bool = true,
         dailyQuotaLimit: Int = APIKey.defaultDailyQuotaLimit, reservedQuota: Int = 0,
         assignedSiteIDs: [UUID] = [], createdAt: Date? = nil) {
        self.id = id; self.name = name; self.keyValue = keyValue
        self.isEnabled = isEnabled; self.dailyQuotaLimit = dailyQuotaLimit
        self.reservedQuota = reservedQuota; self.assignedSiteIDs = assignedSiteIDs
    }
    var hasUnlimitedQuota: Bool { dailyQuotaLimit == APIKey.unlimitedQuota }
    func availableForManualUse(used: Int) -> Int {
        guard !hasUnlimitedQuota else { return Int.max }
        return max(max(dailyQuotaLimit - reservedQuota, 0) - used, 0)
    }
}
