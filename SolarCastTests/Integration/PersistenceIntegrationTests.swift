import XCTest
import SwiftData
@testable import SolarCast

final class PersistenceIntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var forecastRepo: SwiftDataForecastRepository!
    private var siteRepo: SwiftDataPVSiteRepository!
    private var keyRepo: SwiftDataAPIKeyRepository!
    private var quotaRepo: SwiftDataQuotaRepository!

    override func setUp() async throws {
        container    = try ModelContainerFactory.makeInMemoryContainer()
        forecastRepo = SwiftDataForecastRepository(modelContainer: container)
        siteRepo     = SwiftDataPVSiteRepository(modelContainer: container)
        keyRepo      = SwiftDataAPIKeyRepository(modelContainer: container)
        quotaRepo    = SwiftDataQuotaRepository(modelContainer: container)
    }

    // MARK: - PVSite

    func test_site_saveAndFetch_roundtrips() async throws {
        try await siteRepo.save(TestFixtures.siteEast)
        let fetched = try await siteRepo.fetch(id: TestFixtures.siteEastID)
        XCTAssertEqual(fetched?.name, "East")
        XCTAssertEqual(fetched?.colorHex, "#00C853")
        XCTAssertEqual(fetched?.solcastSiteID, "pv_east")
    }

    func test_site_delete_removesFromStore() async throws {
        try await siteRepo.save(TestFixtures.siteEast)
        try await siteRepo.delete(id: TestFixtures.siteEastID)
        let all = try await siteRepo.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func test_site_update_appliesChanges() async throws {
        try await siteRepo.save(TestFixtures.siteEast)
        var updated = TestFixtures.siteEast
        updated.name = "East Updated"
        try await siteRepo.save(updated)
        let fetched = try await siteRepo.fetch(id: TestFixtures.siteEastID)
        XCTAssertEqual(fetched?.name, "East Updated")
    }

    // MARK: - APIKey

    func test_apiKey_saveAndFetch_roundtrips() async throws {
        try await keyRepo.save(TestFixtures.primaryKey)
        let fetched = try await keyRepo.fetch(id: TestFixtures.apiKeyID)
        XCTAssertEqual(fetched?.name, "Primary Key")
        XCTAssertEqual(fetched?.dailyQuotaLimit, 10)
    }

    func test_apiKey_delete() async throws {
        try await keyRepo.save(TestFixtures.primaryKey)
        try await keyRepo.delete(id: TestFixtures.apiKeyID)
        let all = try await keyRepo.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - ForecastPoints

    func test_forecastPoints_upsert_idempotent() async throws {
        try await siteRepo.save(TestFixtures.siteEast)
        let window = SunWindow.testWindow()
        let pt = TestFixtures.point(
            pvSiteID: TestFixtures.siteEastID,
            periodEnd: window.sunrise.addingTimeInterval(1800), pvEstimate: 2.0)
        // Insert twice — should not duplicate
        try await forecastRepo.upsert(points: [pt])
        try await forecastRepo.upsert(points: [pt])
        let fetched = try await forecastRepo.fetchPoints(
            pvSiteIDs: [TestFixtures.siteEastID], from: window.sunrise, to: window.sunset)
        XCTAssertEqual(fetched.count, 1)
    }

    func test_forecastPoints_upsert_updatesExistingValue() async throws {
        try await siteRepo.save(TestFixtures.siteEast)
        let window = SunWindow.testWindow()
        let t = window.sunrise.addingTimeInterval(1800)
        let orig = TestFixtures.point(
            pvSiteID: TestFixtures.siteEastID, periodEnd: t, pvEstimate: 2.0)
        let updated = ForecastPoint(
            pvSiteID: orig.pvSiteID, periodStart: orig.periodStart,
            periodEnd: orig.periodEnd, period: orig.period,
            pvEstimate: 3.5, pvEstimate10: 3.15, pvEstimate90: 3.85, isMock: orig.isMock)
        try await forecastRepo.upsert(points: [orig])
        try await forecastRepo.upsert(points: [updated])
        let fetched = try await forecastRepo.fetchPoints(
            pvSiteIDs: [TestFixtures.siteEastID], from: window.sunrise, to: window.sunset)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].pvEstimate, 3.5, accuracy: 0.001)
    }

    func test_forecastPoints_fetchRange_respectsBounds() async throws {
        try await siteRepo.save(TestFixtures.siteEast)
        let window = SunWindow.testWindow()
        let inside = TestFixtures.point(
            pvSiteID: TestFixtures.siteEastID,
            periodEnd: window.sunrise.addingTimeInterval(1800), pvEstimate: 1.0)
        let outside = TestFixtures.point(
            pvSiteID: TestFixtures.siteEastID,
            periodEnd: window.sunrise.addingTimeInterval(-1800), pvEstimate: 9.9)
        try await forecastRepo.upsert(points: [inside, outside])
        let fetched = try await forecastRepo.fetchPoints(
            pvSiteIDs: [TestFixtures.siteEastID], from: window.sunrise, to: window.sunset)
        XCTAssertTrue(fetched.allSatisfy { $0.pvEstimate < 9.0 })
    }

    func test_forecastPoints_emptyOnFirstRun() async throws {
        // No sites or points inserted — should return empty without error
        let fetched = try await forecastRepo.fetchPoints(
            pvSiteIDs: [UUID()], from: .distantPast, to: .distantFuture)
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Quota (first-run empty state)

    func test_quotaEvents_emptyOnFirstRun() async throws {
        // Critical first-run check: fetching usage events when none exist
        // should return [] not throw an error
        let events = try await quotaRepo.fetchUsageEvents(
            apiKeyID: UUID(), from: .distantPast, to: .distantFuture)
        XCTAssertTrue(events.isEmpty)
    }

    func test_quotaEvents_recordAndFetch() async throws {
        try await keyRepo.save(TestFixtures.primaryKey)
        let event = QuotaUsageEvent(
            apiKeyID: TestFixtures.apiKeyID, timestamp: Date(),
            wasSuccessful: true, purpose: .manual)
        try await quotaRepo.recordUsage(event)
        let fetched = try await quotaRepo.fetchUsageEvents(
            apiKeyID: TestFixtures.apiKeyID, from: .distantPast, to: .distantFuture)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].purpose, .manual)
    }
}
