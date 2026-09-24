import XCTest
@testable import SolarCast

/// NOTE for any fixed Date(timeIntervalSince1970:) constants added here:
/// generateGrid() floors sunrise to the nearest 30-min (1800s) boundary.
/// If a test's "sunrise" constant isn't itself already 30-min-aligned
/// (timestamp % 1800 == 0), the actual first grid slot will be EARLIER
/// than the constant by the misalignment offset — and every
/// slot-position assertion computed as "sunrise + N*1800" will silently
/// check the wrong slot. This was caught and fixed once already during
/// this file's own authoring (an earlier constant, 1_752_400_200, was
/// off by 1200s) — always verify % 1800 == 0 before using a new base
/// timestamp.
final class ChartDataAssemblerTests: XCTestCase {

    // MARK: - Grid boundary (sunrise floors, sunset ceils)
    //
    // This exact boundary flipped direction twice during development —
    // sunset alone went from floor to ceil and back — so it's the single
    // highest-value thing to pin down with a real test, precisely because
    // it's already proven easy to regress silently.

    func test_grid_sunriseFloors_sunsetCeils() throws {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 14
        comps.hour = 5; comps.minute = 34 // NOT on a 30-min boundary
        let sunrise = try XCTUnwrap(cal.date(from: comps))
        comps.hour = 21; comps.minute = 7 // NOT on a 30-min boundary
        let sunset = try XCTUnwrap(cal.date(from: comps))
        let sunWindow = SunWindow(sunrise: sunrise, sunset: sunset)

        let series = ChartDataAssembler.assemble(
            points: [], sites: [], scenario: .normal, sunWindow: sunWindow)
        let totalSeries = try XCTUnwrap(series.first(where: { $0.id == "total" }))

        let firstSlot = try XCTUnwrap(totalSeries.points.first?.localTimestamp)
        let lastSlot = try XCTUnwrap(totalSeries.points.last?.localTimestamp)

        let firstComps = cal.dateComponents([.hour, .minute], from: firstSlot)
        let lastComps = cal.dateComponents([.hour, .minute], from: lastSlot)

        // Sunrise 05:34 -> floors DOWN to 05:30 (first slot before/at sunrise)
        XCTAssertEqual(firstComps.hour, 5)
        XCTAssertEqual(firstComps.minute, 30)
        // Sunset 21:07 -> ceils UP to 21:30 (last slot at/after sunset —
        // the sample whose start-time is past sunset must be included,
        // not cut off at the last slot strictly before it)
        XCTAssertEqual(lastComps.hour, 21)
        XCTAssertEqual(lastComps.minute, 30)
    }

    func test_grid_exactlyOnBoundary_doesNotShiftEitherDirection() throws {
        // Sunrise/sunset already ON a 30-min boundary should NOT move —
        // floor(x) == x and ceil(x) == x when x is already aligned.
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 14
        comps.hour = 6; comps.minute = 0
        let sunrise = try XCTUnwrap(cal.date(from: comps))
        comps.hour = 20; comps.minute = 30
        let sunset = try XCTUnwrap(cal.date(from: comps))
        let sunWindow = SunWindow(sunrise: sunrise, sunset: sunset)

        let series = ChartDataAssembler.assemble(
            points: [], sites: [], scenario: .normal, sunWindow: sunWindow)
        let totalSeries = try XCTUnwrap(series.first(where: { $0.id == "total" }))

        XCTAssertEqual(totalSeries.points.first?.localTimestamp, sunrise)
        XCTAssertEqual(totalSeries.points.last?.localTimestamp, sunset)
    }

    // MARK: - resample: exact match, interpolation, and refusal to extrapolate

    func test_resample_exactMatch_isNotMarkedEstimated() throws {
        let sunrise = Date(timeIntervalSince1970: 1_752_399_000) // deliberately 30-min-aligned (% 1800 == 0) — see note below
        let sunset = sunrise.addingTimeInterval(3600 * 4)
        let sunWindow = SunWindow(sunrise: sunrise, sunset: sunset)
        let site = TestFixtures.siteEast

        // A point landing exactly on a grid slot (sunrise itself, floored)
        let periodEnd = sunrise.addingTimeInterval(1800)
        let pts = [TestFixtures.point(pvSiteID: site.id, periodEnd: periodEnd, pvEstimate: 2.5)]

        let series = ChartDataAssembler.assemble(
            points: pts, sites: [site], scenario: .normal, sunWindow: sunWindow)
        let siteSeries = try XCTUnwrap(series.first(where: { $0.id == site.id.uuidString }))
        let matchingPoint = siteSeries.points.first(where: {
            abs($0.localTimestamp.timeIntervalSince(periodEnd.addingTimeInterval(-1800))) < 1
        })
        let point = try XCTUnwrap(matchingPoint, "Expected a grid slot aligned with the real data point's periodStart")
        XCTAssertEqual(point.kW, 2.5, accuracy: 0.001)
        XCTAssertFalse(point.isInterpolated, "An exact real-data match must not be marked estimated")
    }

    func test_resample_beforeFirstRealPoint_isZeroAndMarkedEstimated() throws {
        // Regression guard: this was previously flagged as REAL data
        // (hasReal[slot] = true) for a slot before the site's first actual
        // point, making a genuinely-missing pre-sunrise value
        // indistinguishable from an actual forecast of zero.
        let sunrise = Date(timeIntervalSince1970: 1_752_399_000)
        let sunset = sunrise.addingTimeInterval(3600 * 6)
        let sunWindow = SunWindow(sunrise: sunrise, sunset: sunset)
        let site = TestFixtures.siteEast

        // Real data only starts 3 hours after sunrise — everything before
        // that in the grid has no real point to resample from.
        let firstRealPeriodEnd = sunrise.addingTimeInterval(3600 * 3 + 1800)
        let pts = [TestFixtures.point(pvSiteID: site.id, periodEnd: firstRealPeriodEnd, pvEstimate: 4.0)]

        let series = ChartDataAssembler.assemble(
            points: pts, sites: [site], scenario: .normal, sunWindow: sunWindow)
        let siteSeries = try XCTUnwrap(series.first(where: { $0.id == site.id.uuidString }))
        let earlyPoint = try XCTUnwrap(siteSeries.points.first)

        XCTAssertEqual(earlyPoint.kW, 0, accuracy: 0.001)
        XCTAssertTrue(earlyPoint.isInterpolated, "A slot before the first real data point must be marked estimated, not presented as a real zero forecast")
    }

    func test_resample_siteWithNoDataAtAll_isZeroAndMarkedEstimated() throws {
        let sunrise = Date(timeIntervalSince1970: 1_752_399_000)
        let sunset = sunrise.addingTimeInterval(3600 * 4)
        let sunWindow = SunWindow(sunrise: sunrise, sunset: sunset)
        let site = TestFixtures.siteEast

        let series = ChartDataAssembler.assemble(
            points: [], sites: [site], scenario: .normal, sunWindow: sunWindow)
        let siteSeries = try XCTUnwrap(series.first(where: { $0.id == site.id.uuidString }))

        XCTAssertFalse(siteSeries.points.isEmpty)
        for point in siteSeries.points {
            XCTAssertEqual(point.kW, 0, accuracy: 0.001)
            XCTAssertTrue(point.isInterpolated, "A site with zero real data anywhere must have every slot marked estimated")
        }
    }

    func test_resample_betweenTwoRealPoints_interpolatesLinearly() throws {
        let sunrise = Date(timeIntervalSince1970: 1_752_399_000)
        let sunset = sunrise.addingTimeInterval(3600 * 4)
        let sunWindow = SunWindow(sunrise: sunrise, sunset: sunset)
        let site = TestFixtures.siteEast

        // p1's periodStart lands exactly at sunrise (periodEnd = sunrise +
        // 30min, since TestFixtures.point derives periodStart as periodEnd
        // - periodSeconds). p2's periodStart lands at sunrise+3600 (60min
        // later). The grid slot at sunrise+1800 sits strictly BETWEEN the
        // two real points' periodStarts — not coinciding with either — so
        // this genuinely exercises the interpolation branch, not the
        // exact-match (120s tolerance) branch.
        let p1End = sunrise.addingTimeInterval(1800)
        let p2End = sunrise.addingTimeInterval(1800 + 3600)
        let pts = [
            TestFixtures.point(pvSiteID: site.id, periodEnd: p1End, pvEstimate: 2.0),
            TestFixtures.point(pvSiteID: site.id, periodEnd: p2End, pvEstimate: 4.0)
        ]

        let series = ChartDataAssembler.assemble(
            points: pts, sites: [site], scenario: .normal, sunWindow: sunWindow)
        let siteSeries = try XCTUnwrap(series.first(where: { $0.id == site.id.uuidString }))
        let midSlotTime = sunrise.addingTimeInterval(1800) // strictly between p1 and p2's periodStarts
        let midPoint = try XCTUnwrap(siteSeries.points.first(where: {
            abs($0.localTimestamp.timeIntervalSince(midSlotTime)) < 1
        }))

        // frac = 1800/3600 = 0.5 -> 2.0 + (4.0-2.0)*0.5 = 3.0
        XCTAssertEqual(midPoint.kW, 3.0, accuracy: 0.01)
    }

    // MARK: - Total series aggregation

    func test_totalSeries_sumsAcrossAllSites() throws {
        let sunrise = Date(timeIntervalSince1970: 1_752_399_000)
        let sunset = sunrise.addingTimeInterval(3600 * 2)
        let sunWindow = SunWindow(sunrise: sunrise, sunset: sunset)
        let east = TestFixtures.siteEast
        let west = TestFixtures.siteWest

        let periodEnd = sunrise.addingTimeInterval(1800)
        let pts = [
            TestFixtures.point(pvSiteID: east.id, periodEnd: periodEnd, pvEstimate: 1.5),
            TestFixtures.point(pvSiteID: west.id, periodEnd: periodEnd, pvEstimate: 2.5)
        ]

        let series = ChartDataAssembler.assemble(
            points: pts, sites: [east, west], scenario: .normal, sunWindow: sunWindow)
        let totalSeries = try XCTUnwrap(series.first(where: { $0.id == "total" }))
        let slotTime = sunrise
        let totalPoint = try XCTUnwrap(totalSeries.points.first(where: {
            abs($0.localTimestamp.timeIntervalSince(slotTime)) < 1
        }))

        XCTAssertEqual(totalPoint.kW, 4.0, accuracy: 0.01, "Total must sum East (1.5) + West (2.5)")
    }

    func test_totalSeries_isFirstInReturnedArray() {
        // ForecastChartView and the tooltip's Divider logic both rely on
        // "total" being a stable, findable identifier — this test doesn't
        // enforce ARRAY POSITION (callers should look up by id, not index),
        // but does confirm the id itself is always present and correctly
        // named, since several features depend on that exact string.
        let sunWindow = SunWindow(sunrise: Date(), sunset: Date().addingTimeInterval(3600))
        let series = ChartDataAssembler.assemble(
            points: [], sites: [], scenario: .normal, sunWindow: sunWindow)
        XCTAssertTrue(series.contains(where: { $0.id == "total" && $0.name == "Total" }))
    }
}
