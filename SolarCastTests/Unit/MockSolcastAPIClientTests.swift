import XCTest
@testable import SolarCast

/// MockSolcastAPIClient's core generation math (shapeFactor, weatherNoise)
/// is entirely private with no @testable seam, and its output is
/// genuinely randomized (Double.random) by design — see the file's own
/// comments on why determinism was deliberately removed. These tests
/// therefore verify INVARIANTS that must hold regardless of which random
/// values were chosen, through the one public method, rather than exact
/// output values, which can't be asserted against a true-random generator.
final class MockSolcastAPIClientTests: XCTestCase {
    private var locationRepo: MockLocationRepository!
    private var pvSiteRepo: MockPVSiteRepository!
    private var apiKeyRepo: MockAPIKeyRepository!
    private var sunWindowCalc: SunWindowCalculator!
    private var client: MockSolcastAPIClient!

    override func setUp() async throws {
        locationRepo = MockLocationRepository()
        pvSiteRepo = MockPVSiteRepository()
        apiKeyRepo = MockAPIKeyRepository()
        sunWindowCalc = SunWindowCalculator(solarCalculator: MockSolarCalculating(stubbedWindow: .testWindow()))
        client = MockSolcastAPIClient(locationRepository: locationRepo, sunWindowCalculator: sunWindowCalc,
                                      pvSiteRepository: pvSiteRepo, apiKeyRepository: apiKeyRepo)
        try await super.setUp()
    }

    // MARK: - Error paths

    func test_fetchForecast_noLocation_throws() async throws {
        await locationRepo.removeLocation()
        let endpoint = SolcastEndpoint(solcastSiteID: "pv_east", apiKeyValue: "sk-test")

        do {
            _ = try await client.fetchForecast(endpoint: endpoint)
            XCTFail("Expected fetchForecast to throw when no location is configured")
        } catch let error as NetworkError {
            if case .unknown = error {
                // expected — the exact message isn't asserted, only that
                // this specific, documented failure mode throws rather
                // than silently returning empty or crashing.
            } else {
                XCTFail("Expected .unknown, got \(error)")
            }
        }
    }

    // MARK: - Structural invariants (slot count, timing)

    func test_fetchForecast_returns7DaysOf30MinSlots() async throws {
        await apiKeyRepo.save(TestFixtures.primaryKey)
        await pvSiteRepo.save(TestFixtures.siteEast)
        let endpoint = SolcastEndpoint(solcastSiteID: "pv_east", apiKeyValue: "sk-test")

        let dtos = try await client.fetchForecast(endpoint: endpoint)

        // 7*24 hours at 30-min slots = 336 total slots — every slot is
        // appended (the loop's `continue` only triggers if a day's sun
        // window fails to resolve, which MockSolarCalculating never does
        // here since it always returns the same stubbed window).
        XCTAssertEqual(dtos.count, 7 * 24 * 2)
    }

    func test_fetchForecast_allPeriodsAre30Minutes() async throws {
        await apiKeyRepo.save(TestFixtures.primaryKey)
        await pvSiteRepo.save(TestFixtures.siteEast)
        let endpoint = SolcastEndpoint(solcastSiteID: "pv_east", apiKeyValue: "sk-test")

        let dtos = try await client.fetchForecast(endpoint: endpoint)

        XCTAssertTrue(dtos.allSatisfy { $0.period == "PT30M" })
    }

    // MARK: - Value invariants (must hold regardless of random values chosen)

    func test_fetchForecast_valuesAreNeverNegative() async throws {
        await apiKeyRepo.save(TestFixtures.primaryKey)
        await pvSiteRepo.save(TestFixtures.siteEast)
        let endpoint = SolcastEndpoint(solcastSiteID: "pv_east", apiKeyValue: "sk-test")

        let dtos = try await client.fetchForecast(endpoint: endpoint)

        XCTAssertTrue(dtos.allSatisfy { $0.pvEstimate >= 0 })
        XCTAssertTrue(dtos.allSatisfy { $0.pvEstimate10 >= 0 })
        XCTAssertTrue(dtos.allSatisfy { $0.pvEstimate90 >= 0 })
    }

    func test_fetchForecast_confidenceBandsBracketTheEstimate() async throws {
        // pvEstimate10 (pessimistic) must be <= pvEstimate, and
        // pvEstimate90 (optimistic) must be >= pvEstimate, for every
        // point — a confidence band that doesn't bracket its own point
        // estimate would be internally inconsistent regardless of the
        // exact random spread chosen.
        await apiKeyRepo.save(TestFixtures.primaryKey)
        await pvSiteRepo.save(TestFixtures.siteEast)
        let endpoint = SolcastEndpoint(solcastSiteID: "pv_east", apiKeyValue: "sk-test")

        let dtos = try await client.fetchForecast(endpoint: endpoint)

        XCTAssertTrue(dtos.allSatisfy { $0.pvEstimate10 <= $0.pvEstimate + 0.0001 })
        XCTAssertTrue(dtos.allSatisfy { $0.pvEstimate90 >= $0.pvEstimate - 0.0001 })
    }

    // MARK: - Capacity guarantee: the real fix from earlier in this session
    //
    // hardCapKW is randomized in [6, 8], split across the REAL number of
    // active sites (assigned to an enabled key), not a fixed assumed
    // maximum of 3 — see the file's own comment on why the old fixed /3
    // split under-delivered for setups with fewer than 3 real sites. This
    // test verifies a single active site's peak can reach a meaningfully
    // large fraction of the possible hard cap range, not capped at 8/3
    // regardless of randomness.

    func test_fetchForecast_singleActiveSite_peakCanExceedThirdOfMaxCap() async throws {
        var key = TestFixtures.primaryKey
        key.isEnabled = true
        await apiKeyRepo.save(key)
        await pvSiteRepo.save(TestFixtures.siteEast) // siteEast's apiKeyID matches primaryKey.id

        let endpoint = SolcastEndpoint(solcastSiteID: "pv_east", apiKeyValue: "sk-test")

        // Run several times (fresh random values each call) and confirm at
        // least one run produces a peak above 8/3 (~2.67) — the ceiling the
        // OLD fixed-/3 design could never exceed even with only 1 real
        // site. A single run could randomly land low; running multiple
        // times makes this a meaningful, not flaky-by-bad-luck, check.
        var sawPeakAboveOldCeiling = false
        for _ in 0..<5 {
            let dtos = try await client.fetchForecast(endpoint: endpoint)
            let peak = dtos.map(\.pvEstimate).max() ?? 0
            if peak > (8.0 / 3.0) {
                sawPeakAboveOldCeiling = true
                break
            }
        }
        XCTAssertTrue(sawPeakAboveOldCeiling, "With only 1 real active site, peak should be able to exceed the old fixed-max-3-sites ceiling (8/3 ~= 2.67) — if it never does across 5 runs, the fix likely regressed back to a fixed split")
    }

    // MARK: - Genuine per-call randomness: the other real fix from this session

    func test_fetchForecast_twoSeparateCalls_produceDifferentOutput() async throws {
        await apiKeyRepo.save(TestFixtures.primaryKey)
        await pvSiteRepo.save(TestFixtures.siteEast)
        let endpoint = SolcastEndpoint(solcastSiteID: "pv_east", apiKeyValue: "sk-test")

        let first = try await client.fetchForecast(endpoint: endpoint)
        let second = try await client.fetchForecast(endpoint: endpoint)

        let firstValues = first.map(\.pvEstimate)
        let secondValues = second.map(\.pvEstimate)

        // Genuinely random per call — the two runs should not be
        // identical. (A prior design used a fixed seed string, which made
        // every call byte-identical forever; this is the regression this
        // test guards against.) Note: with true continuous randomness,
        // two independent calls producing identical output isn't
        // mathematically impossible, only astronomically unlikely across
        // 9 independent Double.random draws feeding 336 derived values —
        // not a real practical flakiness concern, but not an absolute
        // guarantee either.
        XCTAssertNotEqual(firstValues, secondValues, "Two separate fetchForecast calls must produce different output — identical output across calls would indicate a regression back to fixed/deterministic seeding")
    }
}
