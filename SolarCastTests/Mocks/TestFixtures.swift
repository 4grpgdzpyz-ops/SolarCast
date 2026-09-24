import Foundation
@testable import SolarCast

enum TestFixtures {
    static let siteEastID = UUID()
    static let siteWestID = UUID()
    static let apiKeyID   = UUID()

    static var siteEast: PVSite {
        PVSite(id: siteEastID, solcastSiteID: "pv_east", name: "East", colorHex: "#00C853", apiKeyID: apiKeyID)
    }
    static var siteWest: PVSite {
        PVSite(id: siteWestID, solcastSiteID: "pv_west", name: "West", colorHex: "#2196F3", apiKeyID: apiKeyID)
    }
    static var primaryKey: APIKey {
        APIKey(id: apiKeyID, name: "Primary Key", keyValue: "sk-test-1234",
               isEnabled: true, dailyQuotaLimit: 10, reservedQuota: 2,
               assignedSiteIDs: [siteEastID, siteWestID])
    }
    static func dto(pvEstimate: Double, periodEnd: String, period: String = "PT30M") -> ForecastPointDTO {
        ForecastPointDTO(pvEstimate: pvEstimate, pvEstimate10: pvEstimate * 0.9,
                         pvEstimate90: pvEstimate * 1.1, periodEnd: periodEnd, period: period)
    }
    static func point(pvSiteID: UUID = siteEastID, periodEnd: Date,
                      periodSeconds: TimeInterval = 1800, pvEstimate: Double = 1.0,
                      isMock: Bool = false) -> ForecastPoint {
        ForecastPoint(pvSiteID: pvSiteID,
                      periodStart: DateUTCHelpers.periodStart(periodEnd: periodEnd, periodSeconds: periodSeconds),
                      periodEnd: periodEnd, period: "PT30M",
                      pvEstimate: pvEstimate, pvEstimate10: pvEstimate * 0.9, pvEstimate90: pvEstimate * 1.1,
                      isMock: isMock)
    }
}
