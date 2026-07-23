import Foundation
enum FetchPurpose: String, Sendable, CaseIterable {
    case autoFetch           = "autoFetch"
    case autoRefresh         = "autoRefresh"
    case manual              = "manual"
    case appLaunchStaleness  = "appLaunchStaleness"
    /// Not a real API call — recorded when a backup import writes forecast
    /// data directly, so StalenessEvaluator.lastSuccessfulPull sees a
    /// recent "pull" and doesn't immediately re-fetch data that's already
    /// current. Deliberately distinct from .manual, which implies an
    /// actual network call was made; this purpose exists specifically to
    /// be honest that no such call happened.
    case imported            = "imported"
    /// Not a real API call either — recorded by
    /// QuotaManager.forceQuotaExhausted specifically when the actual
    /// Solcast API itself returns HTTP 429 (rate limited), meaning the
    /// real, server-side quota is genuinely exhausted regardless of what
    /// this app's own local event count currently shows. These synthetic
    /// events exist purely to bring the derived usedSinceUTCMidnight count
    /// up to dailyQuotaLimit immediately, distinct from .imported (which
    /// represents genuinely real, successful data arriving by a
    /// different path) since no data arrived here at all — this
    /// purpose's only job is correcting the local count to match reality
    /// after the server has already said no.
    case rateLimitCorrection = "rateLimitCorrection"
}
struct QuotaUsageEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let apiKeyID: UUID
    let timestamp: Date
    let wasSuccessful: Bool
    let purpose: FetchPurpose
    /// Whether this call was made while mock mode was active. Mirrors
    /// ForecastPoint.isMock — without this, a mock-mode fetch (which never
    /// touches Solcast's servers at all) was recorded identically to a
    /// real one, so the API Usage card showed mock activity as if it were
    /// real quota consumption, with no way to filter it back out after
    /// disabling mock mode.
    let isMock: Bool
    /// Whether this event genuinely consumed a real Solcast API call —
    /// a DIFFERENT question from wasSuccessful ("did real forecast data
    /// arrive"). A rate-limited (429), unauthorized (401/403), server
    /// error (5xx), or decode-failure response is a real network
    /// round-trip that reached Solcast's own server and almost
    /// certainly still counts against the real, server-side daily
    /// limit — wasSuccessful is correctly false for all of these (no
    /// data arrived), but they genuinely consumed a call. Only a
    /// PURELY LOCAL failure (invalid URL construction, or no network
    /// connectivity at all — confirmed as the only two NetworkError
    /// cases that never actually reach Solcast's server) should be
    /// false here. Defaults to true, matching the common, real case.
    let consumedRealCall: Bool
    init(id: UUID = UUID(), apiKeyID: UUID, timestamp: Date, wasSuccessful: Bool, purpose: FetchPurpose, isMock: Bool = false, consumedRealCall: Bool = true) {
        self.id = id; self.apiKeyID = apiKeyID; self.timestamp = timestamp
        self.wasSuccessful = wasSuccessful; self.purpose = purpose; self.isMock = isMock
        self.consumedRealCall = consumedRealCall
    }
}
struct QuotaStats: Identifiable, Equatable, Sendable {
    var id: UUID { apiKeyID }
    let apiKeyID: UUID
    let keyName: String
    let limit: Int
    let used: Int
    let reserved: Int
    let assignedSiteNames: [String]
    let lastFetchTimestamp: Date?
    let lastRefreshTimestamp: Date?
    let nextAutoFetchTime: Date?
    let nextAutoRefreshTime: Date?
    let nextAutoRefreshIntervalMinutes: Int?
    let isKeyEnabled: Bool
    var isUnlimited: Bool { limit == 0 }
    var remaining: Int { isUnlimited ? Int.max : max(limit - used, 0) }
}
struct GlobalQuotaStats: Equatable, Sendable {
    let perKey: [QuotaStats]
    var totalLimit: Int? {
        perKey.contains(where: { $0.isUnlimited }) ? nil : perKey.reduce(0) { $0 + $1.limit }
    }
    var totalUsed: Int { perKey.reduce(0) { $0 + $1.used } }
    var totalReserved: Int { perKey.reduce(0) { $0 + $1.reserved } }
}
