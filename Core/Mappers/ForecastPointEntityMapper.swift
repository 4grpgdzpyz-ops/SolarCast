import Foundation
enum ForecastPointEntityMapper {
    static func toDomain(_ e: ForecastPointEntity) -> ForecastPoint? {
        guard let site = e.pvSite else { return nil }
        return ForecastPoint(pvSiteID: site.id, periodStart: e.periodStart, periodEnd: e.periodEnd,
                             period: e.period, pvEstimate: e.pvEstimate,
                             pvEstimate10: e.pvEstimate10, pvEstimate90: e.pvEstimate90,
                             isMock: e.isMock)
    }
    static func makeEntity(from p: ForecastPoint, pvSite: PVSiteEntity) -> ForecastPointEntity {
        ForecastPointEntity(pointID: p.id, pvSite: pvSite, periodStart: p.periodStart,
                            periodEnd: p.periodEnd, period: p.period,
                            pvEstimate: p.pvEstimate, pvEstimate10: p.pvEstimate10, pvEstimate90: p.pvEstimate90,
                            isMock: p.isMock)
    }
    static func apply(_ p: ForecastPoint, to e: ForecastPointEntity) {
        e.periodStart = p.periodStart; e.periodEnd = p.periodEnd; e.period = p.period
        e.pvEstimate = p.pvEstimate; e.pvEstimate10 = p.pvEstimate10; e.pvEstimate90 = p.pvEstimate90
        e.isMock = p.isMock
    }
}
