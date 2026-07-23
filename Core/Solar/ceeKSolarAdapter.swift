import Foundation
import Solar

/// Wraps the Solar library (import Solar) to resolve sunrise/sunset.
/// SolarCalculating protocol is implemented here so the rest of the app
/// never imports Solar directly — only this file does.
struct ceeKSolarAdapter: SolarCalculating {
    func sunWindow(for date: Date, latitude: Double, longitude: Double) -> SunWindow? {
        guard let solar = Solar(for: date, coordinate: .init(latitude: latitude, longitude: longitude)),
              let sunrise = solar.sunrise,
              let sunset  = solar.sunset else { return nil }
        return SunWindow(sunrise: sunrise, sunset: sunset)
    }
}
