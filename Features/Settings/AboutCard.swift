import SwiftUI

struct AboutCard: View {
    static let buildTimestamp: String = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: Date())
    }()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        SettingsCard(title: "About") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version").font(.system(size: 13)).foregroundStyle(Color.scMuted)
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.scText)
                }
                HStack {
                    Text("Build").font(.system(size: 13)).foregroundStyle(Color.scMuted)
                    Spacer()
                    Text(Self.buildTimestamp)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.scText)
                }
            }
        }
    }
}
