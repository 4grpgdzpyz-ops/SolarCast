import Foundation
@testable import SolarCast

struct MockSolarCalculating: SolarCalculating {
    var stubbedWindow: SunWindow?
    func sunWindow(for date: Date, latitude: Double, longitude: Double) -> SunWindow? { stubbedWindow }
}

extension SunWindow {
    static func testWindow(date: Date = Date()) -> SunWindow {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.startOfDay(for: date)
        return SunWindow(sunrise: day.addingTimeInterval(6 * 3600), sunset: day.addingTimeInterval(20 * 3600))
    }
}
