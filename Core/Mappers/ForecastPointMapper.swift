import Foundation
enum ForecastPointMapper {
    enum MappingError: Error, Equatable {
        case invalidPeriodEnd(String)
        case invalidPeriod(String, underlying: String)
    }
    static func map(dto: ForecastPointDTO, pvSiteID: UUID, isMock: Bool) throws -> ForecastPoint {
        guard let periodEnd = DateUTCHelpers.parseSolcastDate(dto.periodEnd) else {
            throw MappingError.invalidPeriodEnd(dto.periodEnd)
        }
        let secs: TimeInterval
        do { secs = try ISO8601PeriodParser.seconds(from: dto.period) }
        catch { throw MappingError.invalidPeriod(dto.period, underlying: "\(error)") }
        return ForecastPoint(pvSiteID: pvSiteID,
            periodStart: DateUTCHelpers.periodStart(periodEnd: periodEnd, periodSeconds: secs),
            periodEnd: periodEnd, period: dto.period,
            pvEstimate: dto.pvEstimate, pvEstimate10: dto.pvEstimate10, pvEstimate90: dto.pvEstimate90,
            isMock: isMock)
    }
    static func mapBatch(dtos: [ForecastPointDTO], pvSiteID: UUID, isMock: Bool) -> (points: [ForecastPoint], errors: [MappingError]) {
        var points: [ForecastPoint] = []; var errors: [MappingError] = []
        for dto in dtos {
            do { points.append(try map(dto: dto, pvSiteID: pvSiteID, isMock: isMock)) }
            catch let e as MappingError { errors.append(e) }
            catch {
                AppLogger.shared.error("ForecastPointMapper: unexpected mapping error for site \(pvSiteID): \(error)")
            }
        }
        return (points, errors)
    }
}
