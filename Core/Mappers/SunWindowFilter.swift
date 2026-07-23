import Foundation
enum SunWindowFilter {
    static func filter(points: [ForecastPoint], sunWindow: SunWindow) -> [ForecastPoint] {
        points.filter { sunWindow.contains($0.periodStart) }
    }
}
