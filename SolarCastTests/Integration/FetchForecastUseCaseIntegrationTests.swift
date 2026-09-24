import XCTest
import SwiftData
@testable import SolarCast

final class FetchForecastUseCaseIntegrationTests: XCTestCase {
    private var apiClient: MockSolcastAPIClient!
    private var forecastRepo: MockForecastRepository!
    private var pvSiteRepo: MockPVSiteRepository!
    private var apiKeyRepo: MockAPIKeyRepository!
    private var quotaRepo: MockQuotaRepository!
    private var locationRepo: MockLocationRepository!
    private var quotaManager: QuotaManager!
    private var sunWindowCalc: SunWindowCalculator!
    private var useCase: FetchForecastUseCase!

    override func setUp() async throws {
        apiClient    = MockSolcastAPIClient()
        forecastRepo = MockForecastRepository()
        pvSiteRepo   = MockPVSiteRepository()
        apiKeyRepo   = MockAPIKeyRepository()
        quotaRepo    = MockQuotaRepository()
        locationRepo = MockLocationRepository()
        quotaManager = QuotaManager(quotaRepository: quotaRepo)
        sunWindowCalc = SunWindowCalculator(
            solarCalculator: MockSolarCalculating(stubbedWindow: .testWindow()))
        try await pvSiteRepo.save(TestFixtures.siteEast)
        try await pvSiteRepo.save(TestFixtures.siteWest)
        try await apiKeyRepo.save(TestFixtures.primaryKey)
        useCase = FetchForecastUseCase(
            apiKeyRepository: apiKeyRepo, pvSiteRepository: pvSiteRepo,
            forecastRepository: forecastRepo, locationRepository: locationRepo,
            quotaManager: quotaManager, sunWindowCalculator: sunWindowCalc,
            parallelFetchCoordinator: ParallelFetchCoordinator(apiClient: apiClient))
    }

    func test_manualFetch_persistsFilteredPoints() async throws {
        let window = SunWindow.testWindow()
        func iso(_ epoch: TimeInterval) -> String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: Date(timeIntervalSince1970: epoch + 1800))
        }
        apiClient.stubbedResult = .success([
            TestFixtures.dto(pvEstimate: 2.0, periodEnd: iso(window.sunrise.timeIntervalSince1970 + 3600)),
            TestFixtures.dto(pvEstimate: 9.9, periodEnd: iso(window.sunrise.timeIntervalSince1970 - 3600)),
        ])
        try await useCase.executeManual()
        let persisted = await forecastRepo.upsertedPoints
        XCTAssertTrue(persisted.allSatisfy { $0.pvEstimate < 9.0 },
                      "Outside-window point (9.9 kW) should have been filtered")
    }

    func test_manualFetch_recordsQuotaUsage() async throws {
        apiClient.stubbedResult = .success([
            TestFixtures.dto(pvEstimate: 1.0, periodEnd: "2026-06-21T10:00:00.0000000Z")])
        try await useCase.executeManual()
        let events = await quotaRepo.events
        XCTAssertEqual(events.count, 2) // one per site
    }

    func test_quotaExhausted_throwsForManualFetch() async throws {
        // Fill quota — manual fetch should now throw FetchError.quotaExhaustedForAllKeys
        let now = Date()
        for _ in 0..<10 {
            try await quotaManager.recordUsage(
                apiKeyID: TestFixtures.apiKeyID, wasSuccessful: true, purpose: .manual, isMock: false, now: now)
        }
        await assertThrowsError(try await useCase.executeManual()) { error in
            guard case FetchError.quotaExhaustedForAllKeys = error else {
                XCTFail("Expected quotaExhaustedForAllKeys, got \(error)")
                return
            }
        }
        // No API calls should have been made
        XCTAssertEqual(apiClient.callCount, 0)
    }

    func test_quotaExhausted_silentForAutoFetch() async throws {
        // Auto fetch should return silently (not throw) when quota is exhausted
        let now = Date()
        for _ in 0..<10 {
            try await quotaManager.recordUsage(
                apiKeyID: TestFixtures.apiKeyID, wasSuccessful: true, purpose: .autoFetch, isMock: false, now: now)
        }
        // Should not throw
        await assertNoThrow(try await useCase.executeAutoFetch())
        XCTAssertEqual(apiClient.callCount, 0)
    }

    // NOTE: both tests below share a real, pre-existing dependency on
    // wall-clock time at the moment the test suite runs — MockSolarCalculating
    // always returns the same fixed 6am-8pm UTC testWindow() regardless of
    // the date it's asked about, while executeAppLaunchIfStale internally
    // uses the real current time. StalenessEvaluator's rules genuinely
    // differ inside vs. outside that window (elapsed-time-based vs.
    // data-existence-based), so if this suite happens to run outside
    // 6am-8pm UTC, these tests exercise a different code path than the one
    // their names describe. Not introduced by this change — inherited from
    // the existing mock design — but worth stating plainly rather than
    // leaving unstated.
    func test_appLaunchFetch_skipsWhenFresh() async throws {
        let engine = SchedulingEngine(sunWindowCalculator: sunWindowCalc,
            forecastRepository: forecastRepo, quotaRepository: quotaRepo,
            pvSiteRepository: pvSiteRepo, apiKeyRepository: apiKeyRepo)
        let coordinator = BGTaskCoordinator(fetchForecastUseCase: useCase, schedulingEngine: engine)
        // A recent successful pull recorded for the primary key — nothing
        // should be considered stale, so no fetch should fire.
        try await quotaRepo.recordUsage(QuotaUsageEvent(
            apiKeyID: TestFixtures.apiKeyID, timestamp: Date().addingTimeInterval(-30 * 60),
            wasSuccessful: true, purpose: .autoFetch))
        let result = try await useCase.executeAppLaunchIfStale(schedulingEngine: engine, bgTaskCoordinator: coordinator)
        XCTAssertEqual(apiClient.callCount, 0)
        if case .notStale = result {} else { XCTFail("Expected .notStale, got \(result)") }
    }

    func test_appLaunchFetch_firesWhenStale() async throws {
        apiClient.stubbedResult = .success([
            TestFixtures.dto(pvEstimate: 1.0, periodEnd: "2026-06-21T10:00:00.0000000Z")])
        let engine = SchedulingEngine(sunWindowCalculator: sunWindowCalc,
            forecastRepository: forecastRepo, quotaRepository: quotaRepo,
            pvSiteRepository: pvSiteRepo, apiKeyRepository: apiKeyRepo)
        let coordinator = BGTaskCoordinator(fetchForecastUseCase: useCase, schedulingEngine: engine)
        // No usage events recorded at all for the primary key — never
        // pulled, so it must be treated as stale (see
        // StalenessEvaluator.lastSuccessfulPull returning nil).
        let result = try await useCase.executeAppLaunchIfStale(schedulingEngine: engine, bgTaskCoordinator: coordinator)
        XCTAssertGreaterThan(apiClient.callCount, 0)
        if case .fetchedSuccessfully = result {} else { XCTFail("Expected .fetchedSuccessfully, got \(result)") }
    }

    func test_onWillFetch_firesOnlyWhenGenuinelyStale_notDuringCheckItself() async throws {
        // Real behavior under test: onWillFetch must fire exactly once,
        // and only on the path where a fetch actually happens — never for
        // .notStale. This is what makes it safe for a caller to drive a
        // "refreshing" UI indicator from it without that indicator ever
        // activating just because a staleness check merely RAN.
        let engine = SchedulingEngine(sunWindowCalculator: sunWindowCalc,
            forecastRepository: forecastRepo, quotaRepository: quotaRepo,
            pvSiteRepository: pvSiteRepo, apiKeyRepository: apiKeyRepo)
        let coordinator = BGTaskCoordinator(fetchForecastUseCase: useCase, schedulingEngine: engine)

        // Case 1: fresh (recent successful pull recorded) — must NOT fire.
        try await quotaRepo.recordUsage(QuotaUsageEvent(
            apiKeyID: TestFixtures.apiKeyID, timestamp: Date().addingTimeInterval(-30 * 60),
            wasSuccessful: true, purpose: .autoFetch))
        var freshCallbackFired = false
        let freshResult = try await useCase.executeAppLaunchIfStale(schedulingEngine: engine, bgTaskCoordinator: coordinator, onWillFetch: {
            freshCallbackFired = true
        })
        if case .notStale = freshResult {} else { XCTFail("Expected .notStale, got \(freshResult)") }
        XCTAssertFalse(freshCallbackFired, "onWillFetch must NOT fire when nothing is stale")

        // Case 2: genuinely stale — must fire exactly once, before the
        // fetch completes (verified indirectly: callCount is still 0 at
        // the moment the callback runs, since the callback is awaited
        // BEFORE execute() is called).
        apiClient.stubbedResult = .success([
            TestFixtures.dto(pvEstimate: 1.0, periodEnd: "2026-06-21T10:00:00.0000000Z")])
        try await quotaRepo.seedEvents([]) // clear the fresh pull recorded above
        var staleCallbackFireCount = 0
        var callCountAtCallbackTime: Int?
        let staleResult = try await useCase.executeAppLaunchIfStale(schedulingEngine: engine, bgTaskCoordinator: coordinator, onWillFetch: {
            staleCallbackFireCount += 1
            callCountAtCallbackTime = apiClient.callCount
        })
        if case .fetchedSuccessfully = staleResult {} else { XCTFail("Expected .fetchedSuccessfully, got \(staleResult)") }
        XCTAssertEqual(staleCallbackFireCount, 1, "onWillFetch must fire exactly once when a fetch genuinely happens")
        XCTAssertEqual(callCountAtCallbackTime, 0, "onWillFetch must be awaited to completion BEFORE the real fetch starts, not after or concurrently")
    }

    func test_noLocation_throwsDescriptiveError() async throws {
        await locationRepo.removeLocation()
        await assertThrowsError(try await useCase.executeManual()) { error in
            guard case FetchError.noLocationConfigured = error else {
                XCTFail("Expected noLocationConfigured, got \(error)")
                return
            }
        }
    }
}
