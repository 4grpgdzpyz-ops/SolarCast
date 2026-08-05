import Foundation
protocol ForecastRepository: Sendable {
    func upsert(points: [ForecastPoint]) async throws
    func fetchPoints(pvSiteIDs: [UUID], from: Date, to: Date) async throws -> [ForecastPoint]
    func deletePoints(matching ids: [String]) async throws
    /// Deletes every stored point whose isMock flag matches the given value.
    /// Used when the mock/real toggle changes, so switching never leaves a
    /// mix of mock and real data sharing the same site/timestamp slots.
    func deleteAllPoints(isMock: Bool) async throws
}
