import XCTest
@testable import SolarCast

final class AutoRefreshIntervalCalculatorTests: XCTestCase {
    func test_unlimited_returnsUnlimitedQuotaInterval() {
        XCTAssertEqual(AutoRefreshIntervalCalculator.computeIntervalMinutes(
            dailyQuotaLimit: 0, autoFetchReservedCalls: 0, sunWindowHours: 14, assignedSiteCount: 2),
            AutoRefreshIntervalCalculator.unlimitedQuotaIntervalMinutes)
    }
    func test_noSites_returnsNil() {
        XCTAssertNil(AutoRefreshIntervalCalculator.computeIntervalMinutes(
            dailyQuotaLimit: 10, autoFetchReservedCalls: 2, sunWindowHours: 14, assignedSiteCount: 0))
    }
    func test_noQuotaLeft_returnsNil() {
        XCTAssertNil(AutoRefreshIntervalCalculator.computeIntervalMinutes(
            dailyQuotaLimit: 2, autoFetchReservedCalls: 2, sunWindowHours: 14, assignedSiteCount: 1))
    }
    func test_neverBelowMinimum() {
        let interval = AutoRefreshIntervalCalculator.computeIntervalMinutes(
            dailyQuotaLimit: 1000, autoFetchReservedCalls: 0, sunWindowHours: 14, assignedSiteCount: 1)
        XCTAssertGreaterThanOrEqual(interval!, AutoRefreshIntervalCalculator.minimumIntervalMinutes)
    }
}
