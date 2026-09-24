import Foundation
struct QuotaWindowTracker: Sendable {
    let quotaRepository: QuotaRepository

    /// Start of the current UTC calendar day at or before `now` —
    /// Solcast's own quota window is calendar-day based (confirmed by
    /// this app's own QuotaReservationPolicy.nextUTCMidnight, the
    /// boundary the daily quota resets at). Delegates to the shared
    /// UTCCalendar utility, so this and every other real UTC-boundary
    /// calculation in the app stay in sync from one, single source.
    private static func startOfUTCDay(for now: Date) -> Date {
        UTCCalendar.calendar.startOfDay(for: now)
    }

    /// Real, genuine quota usage since the last UTC midnight — NOT a
    /// rolling 24h window. A rolling window meant a forced-exhaustion
    /// event (or any real usage) recorded late in one UTC day could
    /// still count against a key for up to 24h after being recorded,
    /// well past Solcast's own real, calendar-day reset — incorrectly
    /// keeping a key blocked even after the actual server-side quota
    /// had already reset. This aligns local tracking with the real
    /// boundary this app has always known about elsewhere
    /// (QuotaReservationPolicy), but hadn't actually used here.
    func usedSinceUTCMidnight(apiKeyID: UUID, now: Date) async throws -> Int {
        try await quotaRepository.fetchUsageEvents(apiKeyID: apiKeyID, from: Self.startOfUTCDay(for: now), to: now)
            // .imported is deliberately excluded — it's a synthetic event
            // recorded so StalenessEvaluator.lastSuccessfulPull sees a
            // fresh "pull" after a backup import (which writes forecast
            // data directly, with no network call to Solcast at all). It
            // was previously indistinguishable from a real call here,
            // since this filter only checked wasSuccessful — meaning an
            // import could genuinely count toward and exhaust a key's
            // daily quota, blocking real fetches for the rest of the day
            // despite zero actual API calls having been made.
            //
            // Counted by consumedRealCall, NOT wasSuccessful — a real,
            // confirmed bug: a rate-limited (429), unauthorized,
            // server-error, or decode-failure response IS a genuine
            // network round-trip that reached Solcast's server and
            // almost certainly still counts against the real,
            // server-side daily limit, even though wasSuccessful is
            // correctly false for it (no data arrived). The old
            // wasSuccessful-only filter silently undercounted true
            // usage by every failed-but-real call, meaning
            // forceQuotaExhausted's own deficit computation (based on
            // this same count) could compute a deficit larger than the
            // real remaining gap — inserting more synthetic events than
            // actually needed, though the end state (fully exhausted)
            // was still correct either way for THAT specific feature.
            // The more consequential fix is this count no longer
            // silently understating real usage in general, for any
            // caller that relies on it.
            .filter { $0.consumedRealCall && $0.purpose != .imported }.count
    }
}
