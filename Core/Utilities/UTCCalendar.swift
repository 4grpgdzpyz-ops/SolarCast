import Foundation

/// Single, real source of truth for "the UTC calendar" — this exact
/// construction (Gregorian calendar, UTC time zone) was independently,
/// separately written in six real files this session (QuotaManager,
/// QuotaWindowTracker, QuotaReservationPolicy, SunWindowCalculator,
/// MockSolcastAPIClient, AppLogger), since Solcast's own real quota
/// reset and this app's own scheduling boundaries are all genuinely
/// UTC-based. Consolidating here means all real callers stay in sync
/// if this construction ever needs to change, rather than six
/// separately-maintained copies risking silent drift.
enum UTCCalendar {
    /// A genuinely fresh Calendar value each time — Calendar is a real,
    /// mutable value type, and returning a shared, cached instance would
    /// risk a caller's own local mutation (e.g. changing firstWeekday)
    /// leaking into every other real caller's copy. This is cheap to
    /// construct, so there's no real, meaningful cost to building it
    /// fresh on every access.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}
