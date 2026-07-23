import XCTest
@testable import SolarCast

final class ScenarioAggregatorTests: XCTestCase {
    func test_sumsMultipleSitesAtSameTimestamp() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let p1 = TestFixtures.point(pvSiteID: TestFixtures.siteEastID, periodEnd: now, pvEstimate: 2.0)
        let p2 = TestFixtures.point(pvSiteID: TestFixtures.siteWestID, periodEnd: now, pvEstimate: 3.0)
        let result = ScenarioAggregator.aggregate(points: [p1, p2], scenario: .normal)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].combinedKW, 5.0, accuracy: 0.001)
    }
    func test_sortsByTimestamp() {
        let t1 = Date(timeIntervalSince1970: 1_750_000_000)
        let t2 = t1.addingTimeInterval(1800)
        let result = ScenarioAggregator.aggregate(
            points: [TestFixtures.point(periodEnd: t2, pvEstimate: 2.0),
                     TestFixtures.point(periodEnd: t1, pvEstimate: 1.0)], scenario: .normal)
        XCTAssertEqual(result[0].combinedKW, 1.0, accuracy: 0.001)
    }
    func test_respectsScenario() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let p = TestFixtures.point(periodEnd: now, pvEstimate: 2.0)
        XCTAssertEqual(ScenarioAggregator.aggregate(points: [p], scenario: .normal)[0].combinedKW,      2.0, accuracy: 0.001)
        XCTAssertEqual(ScenarioAggregator.aggregate(points: [p], scenario: .pessimistic)[0].combinedKW, 1.8, accuracy: 0.001)
        XCTAssertEqual(ScenarioAggregator.aggregate(points: [p], scenario: .optimistic)[0].combinedKW,  2.2, accuracy: 0.001)
    }
}
