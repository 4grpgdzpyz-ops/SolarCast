import XCTest
@testable import SolarCast

final class DateUTCHelpersTests: XCTestCase {
    func test_periodStart_dstSafe() {
        let periodEnd = DateUTCHelpers.parseSolcastDate("2026-03-29T01:00:00.0000000Z")!
        let periodStart = DateUTCHelpers.periodStart(periodEnd: periodEnd, periodSeconds: 1800)
        XCTAssertEqual(periodStart.timeIntervalSince1970, periodEnd.timeIntervalSince1970 - 1800, accuracy: 0.001)
    }
    func test_parseSolcastDate_withFractional()    { XCTAssertNotNil(DateUTCHelpers.parseSolcastDate("2026-06-21T05:00:00.0000000Z")) }
    func test_parseSolcastDate_withoutFractional() { XCTAssertNotNil(DateUTCHelpers.parseSolcastDate("2026-06-21T05:00:00Z")) }
    func test_parseSolcastDate_invalid_returnsNil() { XCTAssertNil(DateUTCHelpers.parseSolcastDate("not-a-date")) }
}
