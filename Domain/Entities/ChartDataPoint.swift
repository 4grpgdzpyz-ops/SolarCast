import Foundation
struct ChartDataPoint: Identifiable, Equatable, Sendable {
    var id: String { "\(seriesID)_\(localTimestamp.timeIntervalSince1970)" }
    let seriesID: String
    let localTimestamp: Date
    let kW: Double
    let isInterpolated: Bool
}
struct ChartSeries: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let colorHex: String
    let points: [ChartDataPoint]
    var isVisible: Bool
}
