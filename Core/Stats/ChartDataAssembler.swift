import Foundation
enum ChartDataAssembler {
    static let gridIntervalMinutes = 30
    static func assemble(points: [ForecastPoint], sites: [PVSite], scenario: Scenario,
                         sunWindow: SunWindow, localTimeZone: TimeZone = .current) -> [ChartSeries] {
        let bySite = Dictionary(grouping: points, by: { $0.pvSiteID })
        let grid = generateGrid(sunWindow: sunWindow)
        var series: [ChartSeries] = []; var totals: [Date: Double] = [:]; var hasReal: [Date: Bool] = [:]
        for site in sites {
            let pts = (bySite[site.id] ?? []).sorted { $0.periodStart < $1.periodStart }
            var sp: [ChartDataPoint] = []
            for slot in grid {
                if pts.isEmpty {
                    // No data for this site at all — this zero is a
                    // placeholder, not a forecast. Must be marked estimated
                    // so downstream UI (dashed lines, tooltips) doesn't
                    // present it as a real value.
                    sp.append(ChartDataPoint(seriesID: site.id.uuidString, localTimestamp: slot, kW: 0, isInterpolated: true))
                    totals[slot, default: 0] += 0
                } else if let rv = resample(at: slot, in: pts, scenario: scenario) {
                    sp.append(ChartDataPoint(seriesID: site.id.uuidString, localTimestamp: slot, kW: rv.kW, isInterpolated: rv.est))
                    totals[slot, default: 0] += rv.kW
                    if !rv.est { hasReal[slot] = true }
                } else {
                    // Slot is before the site's first real point or after its
                    // last. resample() correctly refuses to invent a value
                    // here — zero is our own assumption, not derived from
                    // real data, so it must be marked estimated. Previously
                    // this was flagged as real (hasReal[slot] = true), which
                    // meant a genuinely-missing pre-sunrise/post-sunset value
                    // was indistinguishable from an actual forecast of zero.
                    sp.append(ChartDataPoint(seriesID: site.id.uuidString, localTimestamp: slot, kW: 0, isInterpolated: true))
                    totals[slot, default: 0] += 0
                }
            }
            series.append(ChartSeries(id: site.id.uuidString, name: site.name, colorHex: site.colorHex, points: sp, isVisible: true))
        }
        let totalPoints = grid.map { slot in
            ChartDataPoint(seriesID: "total", localTimestamp: slot, kW: totals[slot, default: 0], isInterpolated: hasReal[slot] != true)
        }
        return [ChartSeries(id: "total", name: "Total", colorHex: "#FF9800", points: totalPoints, isVisible: true)] + series
    }
    private static func generateGrid(sunWindow: SunWindow) -> [Date] {
        // First point = the 30-min slot AT OR BEFORE sunrise (e.g. sunrise
        // 05:34 -> first point 05:30). Last point = the 30-min slot AT OR
        // AFTER sunset (e.g. sunset 21:07 -> last point 21:30) — the sample
        // whose start-time is past sunset must be included, not cut off at
        // the last slot before it. Moon sits at this same last index (see
        // ForecastChartView), so it naturally moves to 21:30 as well.
        let iv = TimeInterval(gridIntervalMinutes * 60)
        let alignedStart = (sunWindow.sunrise.timeIntervalSince1970 / iv).rounded(.down) * iv
        let alignedEnd = (sunWindow.sunset.timeIntervalSince1970 / iv).rounded(.up) * iv
        var slots: [Date] = []
        var c = Date(timeIntervalSince1970: alignedStart)
        let end = Date(timeIntervalSince1970: alignedEnd)
        while c <= end {
            slots.append(c)
            c = c.addingTimeInterval(iv)
        }
        return slots
    }
    private struct RV { let kW: Double; let est: Bool }
    private static func resample(at slot: Date, in pts: [ForecastPoint], scenario: Scenario) -> RV? {
        // Increased tolerance to 120 seconds to handle timezone/rounding differences
        // between the grid and the API data timestamps
        if let exact = pts.first(where: { abs($0.periodStart.timeIntervalSince(slot)) < 120 }) {
            return RV(kW: exact.value(for: scenario), est: false)
        }
        guard let first = pts.first, let last = pts.last,
              slot > first.periodStart, slot < last.periodStart else { return nil }
        guard let before = pts.last(where: { $0.periodStart < slot }),
              let after  = pts.first(where: { $0.periodStart > slot }) else { return nil }
        let span = after.periodStart.timeIntervalSince(before.periodStart)
        guard span > 0 else { return nil }
        let frac = slot.timeIntervalSince(before.periodStart) / span
        return RV(kW: before.value(for: scenario) + (after.value(for: scenario) - before.value(for: scenario)) * frac, est: false)
    }
}
