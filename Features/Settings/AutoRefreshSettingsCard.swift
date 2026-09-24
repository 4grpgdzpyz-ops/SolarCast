import SwiftUI

struct AutoRefreshSettingsCard: View {
    @Binding var autoRefreshEnabled: Bool
    let computedIntervalMinutes: Int?
    let nextAutoRefreshTime: Date?

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        SettingsCard(title: "Auto Refresh") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $autoRefreshEnabled) {
                    Text("Refresh throughout the day").font(.system(size: 13)).foregroundStyle(Color.scText)
                }.tint(Color.scAccent)

                Text("Repeats fetches from sunrise to sunset, spaced automatically based on your remaining daily quota and today's sun window.")
                    .font(.system(size: 11)).foregroundStyle(Color.scMuted)

                if autoRefreshEnabled {
                    if let interval = computedIntervalMinutes {
                        Text("Computed interval: ~\(interval) min")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.scMuted)
                    }
                    if let next = nextAutoRefreshTime {
                        Text("Next refresh: \(Self.fmt.string(from: next))")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.scGreen)
                    }
                }
            }
        }
    }
}
