import Foundation
enum ISO8601PeriodParser {
    enum ParseError: Error, Equatable { case malformedDuration(String) }
    static func seconds(from period: String) throws -> TimeInterval {
        guard period.hasPrefix("PT") else { throw ParseError.malformedDuration(period) }
        let body = period.dropFirst(2)
        var total: TimeInterval = 0, buf = ""
        for char in body {
            if char.isNumber { buf.append(char) }
            else if char == "H" {
                guard let h = Double(buf) else { throw ParseError.malformedDuration(period) }
                total += h * 3600; buf = ""
            } else if char == "M" {
                guard let m = Double(buf) else { throw ParseError.malformedDuration(period) }
                total += m * 60; buf = ""
            } else { throw ParseError.malformedDuration(period) }
        }
        guard total > 0 else { throw ParseError.malformedDuration(period) }
        return total
    }
}
