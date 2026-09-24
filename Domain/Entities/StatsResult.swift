import Foundation
struct StatsResult: Equatable, Sendable {
    let scenario: Scenario
    let date: Date
    let sunWindow: SunWindow
    let averageKW: Double
    let peakKW: Double
    let peakTimestamp: Date
    let totalKWh: Double
    let bestInterval: BestInterval?
}
struct BestInterval: Equatable, Sendable {
    let start: Date
    let end: Date
    let totalKWh: Double
    let averageKW: Double
}
