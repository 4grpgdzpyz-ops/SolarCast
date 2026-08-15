import Foundation
enum ScenarioAggregator {
    struct AggregatedPoint: Equatable, Sendable {
        let timestamp: Date; let combinedKW: Double; let intervalSeconds: TimeInterval
    }
    static func aggregate(points: [ForecastPoint], scenario: Scenario) -> [AggregatedPoint] {
        Dictionary(grouping: points, by: { $0.periodStart }).compactMap { ts, pts -> AggregatedPoint? in
            guard let secs = try? ISO8601PeriodParser.seconds(from: pts[0].period) else { return nil }
            return AggregatedPoint(timestamp: ts, combinedKW: pts.reduce(0) { $0 + $1.value(for: scenario) }, intervalSeconds: secs)
        }.sorted { $0.timestamp < $1.timestamp }
    }
}
