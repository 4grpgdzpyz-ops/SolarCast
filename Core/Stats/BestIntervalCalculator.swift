import Foundation
enum BestIntervalCalculator {
    /// Finds the contiguous window containing peak production.
    /// The window covers all time slots where combined production
    /// is >= 80% of the peak slot's value. This gives a natural
    /// dynamic window — narrow on cloudy days, wide on sunny days.
    static func find(points: [ScenarioAggregator.AggregatedPoint]) -> BestInterval? {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        // Find the peak production value
        let peakKW = sorted.map(\.combinedKW).max() ?? 0
        guard peakKW > 0.01 else { return nil }

        // Threshold: 90% of peak
        let threshold = peakKW * 0.90

        // Find the contiguous region where production >= threshold
        var startIdx: Int?
        var endIdx: Int?
        var bestStart: Int?
        var bestEnd: Int?
        var bestTotal: Double = 0

        for i in sorted.indices {
            if sorted[i].combinedKW >= threshold {
                if startIdx == nil { startIdx = i }
                endIdx = i
            } else {
                // End of a contiguous region
                if let s = startIdx, let e = endIdx {
                    let total = sorted[s...e].reduce(0.0) { $0 + $1.combinedKW * ($1.intervalSeconds / 3600) }
                    if total > bestTotal {
                        bestTotal = total
                        bestStart = s
                        bestEnd = e
                    }
                }
                startIdx = nil
                endIdx = nil
            }
        }
        // Check last region
        if let s = startIdx, let e = endIdx {
            let total = sorted[s...e].reduce(0.0) { $0 + $1.combinedKW * ($1.intervalSeconds / 3600) }
            if total > bestTotal {
                bestTotal = total
                bestStart = s
                bestEnd = e
            }
        }

        guard let bs = bestStart, let be = bestEnd else { return nil }
        let start = sorted[bs].timestamp
        let end = sorted[be].timestamp.addingTimeInterval(sorted[be].intervalSeconds)
        let dur = end.timeIntervalSince(start) / 3600
        return BestInterval(start: start, end: end, totalKWh: bestTotal,
                            averageKW: dur > 0 ? bestTotal / dur : 0)
    }
}
