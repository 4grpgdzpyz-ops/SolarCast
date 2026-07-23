import Foundation
struct FetchTriggerConfiguration: Equatable, Sendable {
    enum AutoFetchTiming: Equatable, Sendable {
        case fixedTime(hour: Int, minute: Int)
        case sunriseRelative(offsetMinutes: Int)
    }
    var autoFetchEnabled: Bool
    var autoFetchTiming: AutoFetchTiming
    var autoRefreshEnabled: Bool
}
