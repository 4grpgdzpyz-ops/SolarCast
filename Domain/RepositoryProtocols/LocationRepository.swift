import Foundation
protocol LocationRepository: Sendable {
    func fetchCurrent() async throws -> UserLocation?
    func save(_ location: UserLocation) async throws
    func delete() async throws
}
