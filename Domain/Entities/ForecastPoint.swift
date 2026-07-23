import Foundation
struct ForecastPoint: Identifiable, Equatable, Sendable {
    // Includes isMock so a real point and a mock point at the same
    // site/timestamp get genuinely DIFFERENT ids, not the same one.
    // ForecastPointEntity.pointID has a real, enforced @Attribute(.unique)
    // constraint — without isMock in this composition, switching modes
    // and fetching would make upsert() match the OTHER mode's existing
    // record by pointID and silently convert it in place (overwriting
    // pvEstimate AND isMock), rather than creating a separate, coexisting
    // entity. This is what actually makes it safe for mock and real data
    // to coexist in storage now that the destructive purge-on-mode-switch
    // was removed (see DIContainer.reloadAPIClient).
    var id: String { "\(pvSiteID.uuidString)_\(periodEnd.timeIntervalSince1970)_\(isMock ? "mock" : "real")" }
    let pvSiteID: UUID
    let periodStart: Date
    let periodEnd: Date
    let period: String
    let pvEstimate: Double
    let pvEstimate10: Double
    let pvEstimate90: Double
    let isMock: Bool
    func value(for scenario: Scenario) -> Double {
        switch scenario {
        case .normal: return pvEstimate
        case .pessimistic: return pvEstimate10
        case .optimistic: return pvEstimate90
        }
    }
}
