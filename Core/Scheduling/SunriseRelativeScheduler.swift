import Foundation
struct SunriseRelativeScheduler: Sendable {
    func resolveTriggerTime(sunWindow: SunWindow, offsetMinutes: Int) -> Date {
        sunWindow.sunrise.addingTimeInterval(TimeInterval(offsetMinutes * 60))
    }
}
