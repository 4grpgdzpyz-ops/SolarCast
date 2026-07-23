import Foundation
protocol SolarCalculating: Sendable {
    func sunWindow(for date: Date, latitude: Double, longitude: Double) -> SunWindow?
}
actor SunWindowCalculator {
    private let solarCalculator: SolarCalculating
    private var cache: [String: SunWindow] = [:]
    init(solarCalculator: SolarCalculating) { self.solarCalculator = solarCalculator }
    func resolve(date: Date, location: UserLocation) -> SunWindow? {
        let key = cacheKey(date: date, location: location)
        if let cached = cache[key] { return cached }
        guard let w = solarCalculator.sunWindow(for: date, latitude: location.latitude, longitude: location.longitude) else { return nil }
        cache[key] = w; return w
    }
    private func cacheKey(date: Date, location: UserLocation) -> String {
        let cal = UTCCalendar.calendar
        return "\(cal.startOfDay(for: date).timeIntervalSince1970)_\(location.latitude)_\(location.longitude)"
    }
}
