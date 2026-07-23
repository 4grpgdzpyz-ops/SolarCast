import Foundation
@testable import SolarCast

actor MockForecastRepository: ForecastRepository {
    var upsertedPoints: [ForecastPoint] = []
    var stubbedPoints: [ForecastPoint] = []
    var upsertCallCount = 0
    /// Seeds data readable via fetchPoints(), separate from upsertedPoints
    /// (which only tracks what upsert() itself received — a write-log, not
    /// pre-existing state). A method, not direct property assignment, to
    /// match this codebase's existing convention for populating
    /// actor-backed mocks (see pvSiteRepo.save(...), apiKeyRepo.save(...)
    /// in FetchForecastUseCaseIntegrationTests).
    func seedStubbedPoints(_ points: [ForecastPoint]) {
        stubbedPoints = points
    }
    func upsert(points: [ForecastPoint]) async throws {
        upsertCallCount += 1; upsertedPoints.append(contentsOf: points)
    }
    func fetchPoints(pvSiteIDs: [UUID], from: Date, to: Date) async throws -> [ForecastPoint] {
        stubbedPoints.filter { pvSiteIDs.contains($0.pvSiteID) && $0.periodStart >= from && $0.periodStart <= to }
    }
    func deletePoints(matching ids: [String]) async throws {
        stubbedPoints.removeAll { ids.contains($0.id) }
    }
    func deleteAllPoints(isMock: Bool) async throws {
        stubbedPoints.removeAll { $0.isMock == isMock }
    }
}
