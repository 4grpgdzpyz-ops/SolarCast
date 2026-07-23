import XCTest
@testable import SolarCast

final class SunWindowTests: XCTestCase {
    func test_roundedHours_exact() {
        let w = SunWindow(sunrise: Date(timeIntervalSince1970: 0),
                          sunset:  Date(timeIntervalSince1970: 14 * 3600))
        XCTAssertEqual(w.roundedHours, 14)
    }
    func test_roundedHours_roundsUp() {
        let w = SunWindow(sunrise: Date(timeIntervalSince1970: 0),
                          sunset:  Date(timeIntervalSince1970: 14 * 3600 + 1800))
        XCTAssertEqual(w.roundedHours, 15)
    }
    func test_contains_inside()  { let w = SunWindow.testWindow(); XCTAssertTrue(w.contains(w.sunrise.addingTimeInterval(3600))) }
    func test_contains_before()  { let w = SunWindow.testWindow(); XCTAssertFalse(w.contains(w.sunrise.addingTimeInterval(-1))) }
    func test_contains_after()   { let w = SunWindow.testWindow(); XCTAssertFalse(w.contains(w.sunset.addingTimeInterval(1))) }
}
