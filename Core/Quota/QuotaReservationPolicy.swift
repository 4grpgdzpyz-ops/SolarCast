import Foundation
struct QuotaReservationPolicy: Sendable {
    /// Next UTC midnight at or after `now` — the boundary the daily quota
    /// itself resets at (Solcast's own quota window is calendar-day based).
    /// Delegates to the shared UTCCalendar utility (Core/Utilities), which
    /// every real UTC-boundary calculation in the app now uses, rather
    /// than an independently-written construction here.
    private static func nextUTCMidnight(after now: Date) -> Date {
        let startOfToday = UTCCalendar.calendar.startOfDay(for: now)
        return UTCCalendar.calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86400)
    }

    /// Reserves quota for an upcoming auto-fetch ONLY if that fetch will
    /// actually consume TODAY's quota allowance — i.e. its scheduled time
    /// falls before the next UTC midnight. A nextAutoFetchDate of nil
    /// (auto-fetch disabled, or genuinely unable to compute a time) means
    /// nothing to reserve for, same as before. But a REAL, enabled
    /// auto-fetch whose next occurrence has already rolled past midnight
    /// into tomorrow's quota window has no claim on TODAY's remaining
    /// calls at all — it'll be paid for out of tomorrow's fresh
    /// allowance, so reserving against today's budget for it was
    /// incorrectly starving today's auto-refresh interval of calls it
    /// could actually have used.
    ///
    /// No manual-call reserve is subtracted from the cap here — there is
    /// no legitimate reason to set aside quota in advance for manual use
    /// anywhere in this app. A manual refresh always triggers a live
    /// recomputation of the auto-refresh interval and a genuine
    /// reschedule of the background job right after it happens
    /// (DashboardViewModel.refresh()), so nothing needs pre-reserving for
    /// something that's corrected live, immediately, the moment it
    /// actually occurs.
    static func computeReservedQuota(dailyQuotaLimit: Int, nextAutoFetchDate: Date?, assignedSiteCount: Int, now: Date = Date()) -> Int {
        guard dailyQuotaLimit != APIKey.unlimitedQuota, assignedSiteCount > 0,
              let nextAutoFetchDate, nextAutoFetchDate < nextUTCMidnight(after: now) else { return 0 }
        return min(assignedSiteCount, dailyQuotaLimit)
    }
}
