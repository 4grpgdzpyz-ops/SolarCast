import XCTest
@testable import SolarCast

final class ForecastPointMapperTests: XCTestCase {
    func test_map_normalizesAllFields() throws {
        let dto = TestFixtures.dto(pvEstimate: 2.5, periodEnd: "2026-06-21T08:00:00.0000000Z")
        let point = try ForecastPointMapper.map(dto: dto, pvSiteID: TestFixtures.siteEastID, isMock: false)
        XCTAssertEqual(point.pvSiteID, TestFixtures.siteEastID)
        XCTAssertEqual(point.pvEstimate, 2.5)
        XCTAssertEqual(point.periodStart.timeIntervalSince1970,
                       point.periodEnd.timeIntervalSince1970 - 1800, accuracy: 0.001)
    }
    func test_map_invalidPeriodEnd_throws() {
        let dto = ForecastPointDTO(pvEstimate:1,pvEstimate10:0.9,pvEstimate90:1.1,periodEnd:"BAD",period:"PT30M")
        XCTAssertThrowsError(try ForecastPointMapper.map(dto: dto, pvSiteID: UUID(), isMock: false))
    }
    func test_mapBatch_isolatesFailures() {
        let good = TestFixtures.dto(pvEstimate: 1.0, periodEnd: "2026-06-21T08:00:00.0000000Z")
        let bad  = ForecastPointDTO(pvEstimate:1,pvEstimate10:0.9,pvEstimate90:1.1,periodEnd:"BAD",period:"PT30M")
        let (points, errors) = ForecastPointMapper.mapBatch(dtos: [good, bad], pvSiteID: UUID(), isMock: false)
        XCTAssertEqual(points.count, 1); XCTAssertEqual(errors.count, 1)
    }
}
