import Foundation
@testable import SolarCast

actor MockAPIKeyRepository: APIKeyRepository {
    var keys: [APIKey] = []
    func fetchAll() async throws -> [APIKey] { keys }
    func fetch(id: UUID) async throws -> APIKey? { keys.first { $0.id == id } }
    func save(_ key: APIKey) async throws {
        if let i = keys.firstIndex(where: { $0.id == key.id }) { keys[i] = key }
        else { keys.append(key) }
    }
    func delete(id: UUID) async throws { keys.removeAll { $0.id == id } }
}
