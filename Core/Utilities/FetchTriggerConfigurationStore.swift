import Foundation
enum FetchTriggerConfigurationStore {
    private static let pfx = "solarcast.fetchTrigger."
    static func save(_ c: FetchTriggerConfiguration) {
        let d = UserDefaults.standard
        d.set(c.autoFetchEnabled,  forKey: pfx + "autoFetchEnabled")
        d.set(c.autoRefreshEnabled, forKey: pfx + "autoRefreshEnabled")
        switch c.autoFetchTiming {
        case .sunriseRelative(let o):
            d.set("sunriseRelative", forKey: pfx + "timingType")
            d.set(o, forKey: pfx + "timingOffset")
        case .fixedTime(let h, let m):
            d.set("fixedTime", forKey: pfx + "timingType")
            d.set(h, forKey: pfx + "timingHour")
            d.set(m, forKey: pfx + "timingMinute")
        }
        AppLogger.shared.info("Settings changed: autoFetch=\(c.autoFetchEnabled), autoRefresh=\(c.autoRefreshEnabled), timing=\(c.autoFetchTiming)")
    }
    static func load() -> FetchTriggerConfiguration {
        let d = UserDefaults.standard
        let type = d.string(forKey: pfx + "timingType") ?? "sunriseRelative"
        let timing: FetchTriggerConfiguration.AutoFetchTiming = type == "fixedTime"
            ? .fixedTime(hour: d.integer(forKey: pfx + "timingHour"),
                         minute: d.integer(forKey: pfx + "timingMinute"))
            : .sunriseRelative(offsetMinutes: d.integer(forKey: pfx + "timingOffset") == 0
                ? -30 : d.integer(forKey: pfx + "timingOffset"))
        return FetchTriggerConfiguration(
            autoFetchEnabled: d.bool(forKey: pfx + "autoFetchEnabled"),
            autoFetchTiming: timing,
            autoRefreshEnabled: d.bool(forKey: pfx + "autoRefreshEnabled"))
    }
}
