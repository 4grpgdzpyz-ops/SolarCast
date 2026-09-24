import Foundation
enum AutoRefreshIntervalCalculator {
    static let minimumIntervalMinutes = 60
    /// Unlimited-quota keys have no real budget constraint at all, so
    /// there's no reason to refresh as aggressively as the absolute
    /// floor allows — 1 hour is a deliberately calmer default for that
    /// case specifically. Kept as its own named constant rather than
    /// reusing minimumIntervalMinutes directly, even though both
    /// currently share the same value (60) — they represent genuinely
    /// different concepts (the deliberate flat interval for unlimited
    /// keys, vs. the floor every OTHER interval is clamped to) that
    /// could diverge again in the future.
    static let unlimitedQuotaIntervalMinutes = 60
    static func computeIntervalMinutes(dailyQuotaLimit: Int, autoFetchReservedCalls: Int,
                                       sunWindowHours: Double, assignedSiteCount: Int) -> Int? {
        guard assignedSiteCount > 0, sunWindowHours > 0 else { return nil }
        guard dailyQuotaLimit != APIKey.unlimitedQuota else { return unlimitedQuotaIntervalMinutes }
        // No manual-call reserve exists anywhere in this app's quota
        // logic — a manual call's real cost is accounted for by
        // recomputing this interval (and rescheduling the background
        // job) fresh immediately after every manual refresh, using the
        // actual remaining quota at that moment, rather than permanently
        // setting aside a fixed call in advance that may never actually
        // be used that day.
        let available = max(dailyQuotaLimit - autoFetchReservedCalls, 0)
        let refreshes = available / assignedSiteCount
        guard refreshes > 0 else { return nil }
        // Divide by (refreshes + 1), not refreshes — splits the window
        // into (refreshes + 1) equal segments (gap before the first
        // execution, refreshes - 1 gaps between consecutive executions,
        // gap after the last), rather than the first execution landing a
        // full interval after the anchor and the last landing almost
        // exactly at the window's end. Verified against real worked
        // examples: 12h remaining / (4+1) = 144min; 15h window / (5+1)
        // = 150min.
        let rawMinutes = (sunWindowHours * 60) / Double(refreshes + 1)
        // Round UP to the nearest 10 minutes — verified: 144 -> 150.
        let roundedUpTo10 = (rawMinutes / 10).rounded(.up) * 10
        return max(Int(roundedUpTo10), minimumIntervalMinutes)
    }
}
