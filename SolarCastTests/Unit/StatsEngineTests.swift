import XCTest
@testable import SolarCast

final class StatsEngineTests: XCTestCase {
    private var window: SunWindow!
    override func setUp() { super.setUp(); window = SunWindow.testWindow() }

    private func pts(_ values: [Double]) -> [ForecastPoint] {
        values.enumerated().map { i, v in
            TestFixtures.point(periodEnd: window.sunrise.addingTimeInterval(Double(i + 1) * 1800), pvEstimate: v)
        }
    }

    func test_empty_returnsZero() {
        let r = StatsEngine.compute(points: [], scenario: .normal, date: Date(), sunWindow: window)
        XCTAssertEqual(r.totalKWh, 0); XCTAssertEqual(r.peakKW, 0)
    }
    func test_totalKWh() {
        let r = StatsEngine.compute(points: pts([2,2,2,2]), scenario: .normal, date: Date(), sunWindow: window)
        XCTAssertEqual(r.totalKWh, 4.0, accuracy: 0.01)
    }
    func test_peakKW() {
        let r = StatsEngine.compute(points: pts([1,3,2,0.5]), scenario: .normal, date: Date(), sunWindow: window)
        XCTAssertEqual(r.peakKW, 3.0, accuracy: 0.001)
    }
    func test_globalAggregation() {
        let t = window.sunrise.addingTimeInterval(1800)
        let east = TestFixtures.point(pvSiteID: TestFixtures.siteEastID, periodEnd: t, pvEstimate: 2.0)
        let west = TestFixtures.point(pvSiteID: TestFixtures.siteWestID, periodEnd: t, pvEstimate: 3.0)
        let r = StatsEngine.compute(points: [east, west], scenario: .normal, date: Date(), sunWindow: window)
        XCTAssertEqual(r.peakKW, 5.0, accuracy: 0.001)
    }
    func test_noInternalWindowFiltering_includesAllProvidedPoints() {
        // StatsEngine previously re-filtered to sunWindow.contains(...)
        // internally, discarding anything outside it regardless of what
        // the caller fetched. Removed so ComputeStatsUseCase's now-widened
        // fetch (matching BuildChartDataUseCase's own sunrise-30min to
        // sunset+30min window) isn't silently narrowed back down here —
        // Average/Peak/Total should reflect the exact same dataset the
        // chart uses, boundary points included, not a stricter subset.
        let before = TestFixtures.point(periodEnd: window.sunrise.addingTimeInterval(-60), pvEstimate: 9.9)
        let inside = TestFixtures.point(periodEnd: window.sunrise.addingTimeInterval(1800), pvEstimate: 1.0)
        let r = StatsEngine.compute(points: [before, inside], scenario: .normal, date: Date(), sunWindow: window)
        XCTAssertEqual(r.peakKW, 9.9, accuracy: 0.001)
    }
}
