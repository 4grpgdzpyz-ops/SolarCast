import Foundation
protocol APIKeyRepository: Sendable {
    func fetchAll() async throws -> [APIKey]
    func fetch(id: UUID) async throws -> APIKey?
    func save(_ key: APIKey) async throws
    func delete(id: UUID) async throws
}
