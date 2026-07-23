import XCTest
@testable import SolarCast

final class QuotaManagerTests: XCTestCase {
    private var repo: MockQuotaRepository!
    private var manager: QuotaManager!
    private var key: APIKey!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        repo = MockQuotaRepository(); manager = QuotaManager(quotaRepository: repo)
        key = TestFixtures.primaryKey
    }

    func test_disabledKey_returnsFalse() async throws {
        var k = key!; k.isEnabled = false
        let result = try await manager.canMakeCall(apiKey: k, purpose: .manual, now: now)
        XCTAssertFalse(result)
    }
    func test_underLimit_returnsTrue() async throws {
        XCTAssertTrue(try await manager.canMakeCall(apiKey: key, purpose: .manual, now: now))
    }
    func test_atLimit_returnsFalse() async throws {
        for _ in 0..<10 { try await manager.recordUsage(apiKeyID: key.id, wasSuccessful: true, purpose: .manual, isMock: false, now: now) }
        XCTAssertFalse(try await manager.canMakeCall(apiKey: key, purpose: .manual, now: now))
    }
    func test_manualBlockedByReservation_autoStillAllowed() async throws {
        for _ in 0..<8 { try await manager.recordUsage(apiKeyID: key.id, wasSuccessful: true, purpose: .manual, isMock: false, now: now) }
        XCTAssertFalse(try await manager.canMakeCall(apiKey: key, purpose: .manual,    now: now))
        XCTAssertTrue( try await manager.canMakeCall(apiKey: key, purpose: .autoFetch, now: now))
    }
    func test_rollingWindow_excludesOldEvents() async throws {
        let old = now.addingTimeInterval(-25 * 3600)
        try await manager.recordUsage(apiKeyID: key.id, wasSuccessful: true, purpose: .manual, isMock: false, now: old)
        XCTAssertTrue(try await manager.canMakeCall(apiKey: key, purpose: .manual, now: now))
    }
}
