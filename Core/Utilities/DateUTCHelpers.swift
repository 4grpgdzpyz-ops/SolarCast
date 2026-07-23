import Foundation
enum DateUTCHelpers {
    static let solcastISO8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let fallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parseSolcastDate(_ s: String) -> Date? {
        solcastISO8601Formatter.date(from: s) ?? fallbackFormatter.date(from: s)
    }
    /// DST-safe: raw TimeInterval arithmetic, never Calendar subtraction.
    static func periodStart(periodEnd: Date, periodSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: periodEnd.timeIntervalSince1970 - periodSeconds)
    }
}
