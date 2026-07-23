import XCTest
@testable import SolarCast

final class ISO8601PeriodParserTests: XCTestCase {
    func test_PT30M_returns1800() throws { XCTAssertEqual(try ISO8601PeriodParser.seconds(from: "PT30M"), 1800) }
    func test_PT5M_returns300()  throws { XCTAssertEqual(try ISO8601PeriodParser.seconds(from: "PT5M"),  300)  }
    func test_PT1H_returns3600() throws { XCTAssertEqual(try ISO8601PeriodParser.seconds(from: "PT1H"),  3600) }
    func test_PT1H30M_returns5400() throws { XCTAssertEqual(try ISO8601PeriodParser.seconds(from: "PT1H30M"), 5400) }
    func test_emptyString_throws()      { XCTAssertThrowsError(try ISO8601PeriodParser.seconds(from: "")) }
    func test_missingPTPrefix_throws()  { XCTAssertThrowsError(try ISO8601PeriodParser.seconds(from: "30M")) }
    func test_zeroDuration_throws()     { XCTAssertThrowsError(try ISO8601PeriodParser.seconds(from: "PT0M")) }
}
