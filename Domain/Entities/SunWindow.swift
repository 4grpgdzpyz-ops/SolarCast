import Foundation
struct SunWindow: Equatable, Sendable {
    let sunrise: Date
    let sunset: Date
    let roundedHours: Int
    init(sunrise: Date, sunset: Date) {
        self.sunrise = sunrise; self.sunset = sunset
        self.roundedHours = Int(((sunset.timeIntervalSince(sunrise)) / 3600.0).rounded())
    }
    func contains(_ date: Date) -> Bool { date >= sunrise && date <= sunset }
}
