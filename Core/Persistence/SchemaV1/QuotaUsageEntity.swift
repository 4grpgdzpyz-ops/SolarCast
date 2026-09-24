import Foundation
import SwiftData
@Model final class QuotaUsageEntity {
    @Attribute(.unique) var id: UUID
    var apiKey: APIKeyEntity?
    var timestamp: Date; var wasSuccessful: Bool; var purposeRawValue: String
    /// Mirrors ForecastPointEntity.isMock — see QuotaUsageEvent.isMock.
    var isMock: Bool
    /// Mirrors QuotaUsageEvent.consumedRealCall — see that type's own
    /// doc comment for the full reasoning. Defaulted to true directly
    /// in the property declaration (not just in init below) — required
    /// for SwiftData's lightweight migration to safely backfill this
    /// value for rows already persisted before this property existed,
    /// rather than fail to decode them.
    var consumedRealCall: Bool = true
    init(id: UUID, apiKey: APIKeyEntity?, timestamp: Date, wasSuccessful: Bool, purposeRawValue: String, isMock: Bool = false, consumedRealCall: Bool = true) {
        self.id = id; self.apiKey = apiKey; self.timestamp = timestamp
        self.wasSuccessful = wasSuccessful; self.purposeRawValue = purposeRawValue; self.isMock = isMock
        self.consumedRealCall = consumedRealCall
    }
}
