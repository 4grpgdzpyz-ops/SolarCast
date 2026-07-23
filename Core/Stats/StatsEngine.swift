import Foundation
enum StatsEngine {
    static func compute(points: [ForecastPoint], scenario: Scenario, date: Date,
                        sunWindow: SunWindow) -> StatsResult {
        // Previously re-filtered to sunWindow.contains(periodStart) here,
        // which discarded the boundary points (one slot before sunrise,
        // one after sunset) even after the fetch itself was widened to
        // include them — meaning the total STILL excluded data the chart
        // includes. Removed so this genuinely computes from the same
        // dataset ComputeStatsUseCase now fetches (matching
        // BuildChartDataUseCase's own window exactly) and the chart
        // itself displays, with no additional narrowing step in between.
        let agg = ScenarioAggregator.aggregate(points: points, scenario: scenario)
        guard !agg.isEmpty else {
            return StatsResult(scenario: scenario, date: date, sunWindow: sunWindow,
                               averageKW: 0, peakKW: 0, peakTimestamp: sunWindow.sunrise, totalKWh: 0, bestInterval: nil)
        }
        let total = agg.reduce(0.0) { $0 + ($1.combinedKW * ($1.intervalSeconds / 3600)) }
        let avg = sunWindow.roundedHours > 0 ? total / Double(sunWindow.roundedHours) : 0
        let peak = agg.max(by: { $0.combinedKW < $1.combinedKW })!
        return StatsResult(scenario: scenario, date: date, sunWindow: sunWindow,
                           averageKW: avg, peakKW: peak.combinedKW, peakTimestamp: peak.timestamp,
                           totalKWh: total,
                           bestInterval: BestIntervalCalculator.find(points: agg))
    }
}
