import XCTest
@testable import SolarCast

/// NOTE: StalenessEvaluator determines a key's assigned sites via
/// PVSite.apiKeyID == key.id (see StalenessEvaluator.swift:
/// `allSites.filter { $0.apiKeyID == key.id }`) — it never reads
/// APIKey.assignedSiteIDs. TestFixtures.siteEast/.siteWest are already
/// constructed with apiKeyID == TestFixtures.apiKeyID, matching
/// TestFixtures.primaryKey's id by default, so most tests below need no
/// explicit site-assignment wiring at all. Only the multi-key test
/// reassigns PVSite.apiKeyID explicitly, since it uses keys with
/// different, freshly-generated IDs.
final class StalenessEvaluatorTests: XCTestCase {
    private var forecastRepo: MockForecastRepository!
    private var quotaRepo: MockQuotaRepository!
    private var pvSiteRepo: MockPVSiteRepository!
    private var sunWindowCalc: SunWindowCalculator!
    private var location: UserLocation!

    override func setUp() async throws {
        forecastRepo = MockForecastRepository()
        quotaRepo = MockQuotaRepository()
        pvSiteRepo = MockPVSiteRepository()
        location = UserLocation(name: "Test Location", latitude: 45.0, longitude: 10.0)
        try await super.setUp()
    }

    /// Builds a fresh evaluator with a sun window covering the given
    /// [sunriseHour, sunsetHour) range on `now`'s calendar day (UTC) — a
    /// new SunWindowCalculator per call, so its internal cache never
    /// leaks between test cases.
    private func makeEvaluator(sunriseHour: Int, sunsetHour: Int, now: Date) -> StalenessEvaluator {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.startOfDay(for: now)
        let window = SunWindow(sunrise: day.addingTimeInterval(TimeInterval(sunriseHour * 3600)),
                               sunset: day.addingTimeInterval(TimeInterval(sunsetHour * 3600)))
        sunWindowCalc = SunWindowCalculator(solarCalculator: MockSolarCalculating(stubbedWindow: window))
        return StalenessEvaluator(forecastRepository: forecastRepo, quotaRepository: quotaRepo,
                                  pvSiteRepository: pvSiteRepo, sunWindowCalculator: sunWindowCalc)
    }

    // MARK: - Disabled keys are always skipped

    func test_disabledKey_isNeverStale_regardlessOfState() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let evaluator = makeEvaluator(sunriseHour: 6, sunsetHour: 20, now: now)

        var key = TestFixtures.primaryKey
        key.isEnabled = false
        // No forecast data at all, no usage events at all — every signal
        // that WOULD make an enabled key stale is present, but a disabled
        // key must never be evaluated, let alone flagged.
        let staleIDs = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: true, nextAutoFetchDate: nil, location: location, now: now)

        XCTAssertTrue(staleIDs.isEmpty, "A disabled key must never be flagged stale")
    }

    // MARK: - Outside sun window: data-existence check

    func test_outsideSunWindow_missingTodayData_isStale() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        // now = 03:00 UTC, well before the 06:00-20:00 sun window
        let now = cal.date(bySettingHour: 3, minute: 0, second: 0, of: Date())!
        let evaluator = makeEvaluator(sunriseHour: 6, sunsetHour: 20, now: now)

        await pvSiteRepo.save(TestFixtures.siteEast)
        let key = TestFixtures.primaryKey
        // forecastRepo has zero stored points for this site at all.

        let staleIDs = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: true, nextAutoFetchDate: nil, location: location, now: now)

        XCTAssertEqual(staleIDs, [key.id], "A key whose assigned site has NO data for today must be stale outside the sun window")
    }

    func test_outsideSunWindow_hasTodayData_isFresh() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(bySettingHour: 3, minute: 0, second: 0, of: Date())!
        let evaluator = makeEvaluator(sunriseHour: 6, sunsetHour: 20, now: now)

        await pvSiteRepo.save(TestFixtures.siteEast)
        let key = TestFixtures.primaryKey
        // Give the site a real point stored for TODAY (within [todayStart, todayEnd)).
        let todayStart = cal.startOfDay(for: now)
        await forecastRepo.seedStubbedPoints([
            TestFixtures.point(pvSiteID: TestFixtures.siteEastID, periodEnd: todayStart.addingTimeInterval(3600))
        ])

        let staleIDs = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: true, nextAutoFetchDate: nil, location: location, now: now)

        XCTAssertTrue(staleIDs.isEmpty, "A key whose assigned site already has data for today must NOT be stale outside the sun window, regardless of how long ago it was fetched")
    }

    // MARK: - Inside sun window: elapsed-time-since-last-pull

    func test_insideSunWindow_neverPulled_isStale() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let evaluator = makeEvaluator(sunriseHour: 6, sunsetHour: 20, now: now)

        await pvSiteRepo.save(TestFixtures.siteEast)
        let key = TestFixtures.primaryKey
        // quotaRepo has zero usage events — key was never successfully pulled.

        let staleIDs = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: true, nextAutoFetchDate: nil, location: location, now: now)

        XCTAssertEqual(staleIDs, [key.id], "A key with no successful pull recorded at all must be stale inside the sun window")
    }

    func test_insideSunWindow_autoRefreshDisabled_usesFlat3HourThreshold() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let evaluator = makeEvaluator(sunriseHour: 6, sunsetHour: 20, now: now)

        await pvSiteRepo.save(TestFixtures.siteEast)
        let key = TestFixtures.primaryKey

        // Last successful pull was 2 hours ago — clearly under the 3h
        // disabled-mode threshold, so should be fresh.
        await quotaRepo.seedEvents([
            QuotaUsageEvent(apiKeyID: key.id, timestamp: now.addingTimeInterval(-2 * 3600),
                            wasSuccessful: true, purpose: .autoFetch)
        ])
        let freshResult = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: false, nextAutoFetchDate: nil, location: location, now: now)
        XCTAssertTrue(freshResult.isEmpty, "2h elapsed, under the 3h disabled-mode threshold, should be fresh")

        // Last successful pull was 4 hours ago — clearly over the 3h threshold.
        await quotaRepo.seedEvents([
            QuotaUsageEvent(apiKeyID: key.id, timestamp: now.addingTimeInterval(-4 * 3600),
                            wasSuccessful: true, purpose: .autoFetch)
        ])
        let staleResult = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: false, nextAutoFetchDate: nil, location: location, now: now)
        XCTAssertEqual(staleResult, [key.id], "4h elapsed, over the 3h disabled-mode threshold, should be stale")
    }

    func test_insideSunWindow_autoRefreshEnabled_usesKeysOwnComputedInterval() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let sunriseHour = 6, sunsetHour = 20
        let evaluator = makeEvaluator(sunriseHour: sunriseHour, sunsetHour: sunsetHour, now: now)

        await pvSiteRepo.save(TestFixtures.siteEast)
        var key = TestFixtures.primaryKey
        key.dailyQuotaLimit = 10

        // Independently compute the expected interval using the same
        // calculator the evaluator itself calls, so this test verifies
        // the evaluator actually USES that computation rather than some
        // other number — not a hand-derived expectation that could drift
        // from the real formula. sunWindowHours is derived from an actual
        // SunWindow built from the SAME sunriseHour/sunsetHour passed to
        // makeEvaluator above (not a hand-typed literal) — this way the
        // expectation automatically tracks the real fixture, rather than
        // silently going stale if the test's sun window were ever
        // changed to model a shorter day (e.g. winter).
        let testWindow = SunWindow(sunrise: cal.startOfDay(for: now).addingTimeInterval(TimeInterval(sunriseHour * 3600)),
                                   sunset: cal.startOfDay(for: now).addingTimeInterval(TimeInterval(sunsetHour * 3600)))
        let reserved = QuotaReservationPolicy.computeReservedQuota(
            dailyQuotaLimit: key.dailyQuotaLimit, nextAutoFetchDate: nil, assignedSiteCount: 1)
        let expectedIntervalMinutes = try XCTUnwrap(AutoRefreshIntervalCalculator.computeIntervalMinutes(
            dailyQuotaLimit: key.dailyQuotaLimit, autoFetchReservedCalls: reserved,
            sunWindowHours: Double(testWindow.roundedHours), assignedSiteCount: 1))

        // Just under the computed interval -> fresh.
        await quotaRepo.seedEvents([
            QuotaUsageEvent(apiKeyID: key.id, timestamp: now.addingTimeInterval(-TimeInterval(expectedIntervalMinutes * 60) + 60),
                            wasSuccessful: true, purpose: .autoRefresh)
        ])
        let freshResult = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: true, nextAutoFetchDate: nil, location: location, now: now)
        XCTAssertTrue(freshResult.isEmpty, "Just under the key's own computed interval should be fresh")

        // Just over the computed interval -> stale.
        await quotaRepo.seedEvents([
            QuotaUsageEvent(apiKeyID: key.id, timestamp: now.addingTimeInterval(-TimeInterval(expectedIntervalMinutes * 60) - 60),
                            wasSuccessful: true, purpose: .autoRefresh)
        ])
        let staleResult = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: true, nextAutoFetchDate: nil, location: location, now: now)
        XCTAssertEqual(staleResult, [key.id], "Just over the key's own computed interval should be stale")
    }

    func test_insideSunWindow_onlyFailedPulls_treatedAsNeverPulled() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let evaluator = makeEvaluator(sunriseHour: 6, sunsetHour: 20, now: now)

        await pvSiteRepo.save(TestFixtures.siteEast)
        let key = TestFixtures.primaryKey

        // A recent event exists, but it FAILED — lastSuccessfulPull only
        // considers wasSuccessful == true, so this must not count.
        await quotaRepo.seedEvents([
            QuotaUsageEvent(apiKeyID: key.id, timestamp: now.addingTimeInterval(-60),
                            wasSuccessful: false, purpose: .autoFetch)
        ])
        let staleIDs = await evaluator.staleAPIKeys(apiKeys: [key], autoRefreshEnabled: true, nextAutoFetchDate: nil, location: location, now: now)

        XCTAssertEqual(staleIDs, [key.id], "Only a failed pull exists — must be treated the same as never having pulled at all")
    }

    // MARK: - Multiple keys: only the actually-stale ones are returned

    func test_multipleKeys_onlyStaleOnesReturned() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let evaluator = makeEvaluator(sunriseHour: 6, sunsetHour: 20, now: now)

        let freshKeyID = UUID()
        let freshKey = APIKey(id: freshKeyID, name: "Fresh Key", keyValue: "sk-fresh",
                              isEnabled: true, dailyQuotaLimit: 10, reservedQuota: 2)
        var eastSite = TestFixtures.siteEast
        eastSite.apiKeyID = freshKeyID
        await pvSiteRepo.save(eastSite)

        let staleKeyID = UUID()
        let staleKey = APIKey(id: staleKeyID, name: "Stale Key", keyValue: "sk-stale",
                              isEnabled: true, dailyQuotaLimit: 10, reservedQuota: 2)
        var westSite = TestFixtures.siteWest
        westSite.apiKeyID = staleKeyID
        await pvSiteRepo.save(westSite)

        // Fresh key: pulled 1 minute ago.
        // Stale key: never pulled.
        await quotaRepo.seedEvents([
            QuotaUsageEvent(apiKeyID: freshKeyID, timestamp: now.addingTimeInterval(-60),
                            wasSuccessful: true, purpose: .autoFetch)
        ])

        let staleIDs = await evaluator.staleAPIKeys(apiKeys: [freshKey, staleKey], autoRefreshEnabled: false, nextAutoFetchDate: nil, location: location, now: now)

        XCTAssertEqual(staleIDs, [staleKeyID], "Only the genuinely stale key should be returned, not the fresh one")
    }
}
