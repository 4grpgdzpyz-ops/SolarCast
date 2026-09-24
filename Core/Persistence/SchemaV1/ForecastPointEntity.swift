import Foundation
import SwiftData
@Model final class ForecastPointEntity {
    @Attribute(.unique) var pointID: String
    var pvSite: PVSiteEntity?
    var periodStart: Date; var periodEnd: Date; var period: String
    var pvEstimate: Double; var pvEstimate10: Double; var pvEstimate90: Double
    /// Whether this point came from MockSolcastAPIClient rather than the
    /// real Solcast API. Without this, toggling mock mode and fetching
    /// would silently overwrite real forecast values at matching
    /// timestamps (pointID collides on site+time only, not source), and
    /// switching back would leave a mix of real and mock points with no
    /// way to tell which is which.
    var isMock: Bool
    init(pointID: String, pvSite: PVSiteEntity?, periodStart: Date, periodEnd: Date,
         period: String, pvEstimate: Double, pvEstimate10: Double, pvEstimate90: Double,
         isMock: Bool = false) {
        self.pointID = pointID; self.pvSite = pvSite; self.periodStart = periodStart
        self.periodEnd = periodEnd; self.period = period; self.pvEstimate = pvEstimate
        self.pvEstimate10 = pvEstimate10; self.pvEstimate90 = pvEstimate90
        self.isMock = isMock
    }
}
