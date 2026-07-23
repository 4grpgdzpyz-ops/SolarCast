import SwiftUI

struct APIUsageCard: View {
    let quota: GlobalQuotaStats
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("API Usage")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.scText)
                .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 8)

            ForEach(quota.perKey) { keyStats in
                VStack(alignment: .leading, spacing: 6) {
                    // Key name
                    HStack {
                        Text(keyStats.keyName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.scText)
                        if !keyStats.isKeyEnabled {
                            Text("DISABLED")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.scRed.opacity(0.15))
                                .foregroundStyle(Color.scRed)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    // Site names + usage fraction
                    HStack {
                        Text(keyStats.assignedSiteNames.isEmpty ? "No sites assigned"
                             : keyStats.assignedSiteNames.joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(Color.scMuted)
                        Spacer()
                        Text(keyStats.isUnlimited ? "Unlimited" : "\(keyStats.used) / \(keyStats.limit)")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(usageColor(keyStats))
                    }

                    // Progress bar
                    if !keyStats.isUnlimited {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(Color.scSurfaceMuted)
                                RoundedRectangle(cornerRadius: 4).fill(usageColor(keyStats))
                                    .frame(width: geo.size.width * fillFraction(keyStats))
                            }
                        }.frame(height: 4)
                    }

                    if keyStats.isKeyEnabled {
                        HStack(alignment: .top) {
                            Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 2) {
                                GridRow {
                                    Text(keyStats.lastFetchTimestamp.map { "Last fetch: \(Self.fmt.string(from: $0))" } ?? "No fetch yet")
                                        .font(.system(size: 10)).foregroundStyle(Color.scMuted)
                                    Text("•") // Bullet (U+2022)
                                        .font(.system(size: 13)).foregroundStyle(Color.scMuted)
                                    if let next = keyStats.nextAutoFetchTime {
                                        Text("Next fetch: \(Self.fmt.string(from: next))")
                                            .font(.system(size: 10)).foregroundStyle(Color.scGreen)
                                    } else {
                                        Text("Auto fetch disabled")
                                            .font(.system(size: 10)).foregroundStyle(Color.scMuted)
                                    }
                                }
                                GridRow {
                                    Text(keyStats.lastRefreshTimestamp.map { "Last refresh: \(Self.fmt.string(from: $0))" } ?? "No refresh yet")
                                        .font(.system(size: 10)).foregroundStyle(Color.scMuted)
                                    Text("•") // Bullet (U+2022)
                                        .font(.system(size: 13)).foregroundStyle(Color.scMuted)
                                    if let next = keyStats.nextAutoRefreshTime {
                                        Text("Next refresh: \(Self.fmt.string(from: next))")
                                            .font(.system(size: 10)).foregroundStyle(Color.scGreen)
                                    } else {
                                        Text("Auto refresh disabled")
                                            .font(.system(size: 10)).foregroundStyle(Color.scMuted)
                                    }
                                }
                            }
                            Spacer()
                            if !keyStats.isUnlimited {
                                Text("\(keyStats.remaining) left")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.scText)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .overlay(Divider(), alignment: .top)
            }
        }
        .background(Color.scCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.scBorder, lineWidth: 1))
    }

    private func usageColor(_ s: QuotaStats) -> Color {
        guard !s.isUnlimited, s.limit > 0 else { return .scGreen }
        let r = Double(s.used) / Double(s.limit)
        return r >= 0.8 ? .scRed : r >= 0.5 ? .scOrange : .scGreen
    }
    private func fillFraction(_ s: QuotaStats) -> Double {
        guard s.limit > 0 else { return 0 }
        return min(1, Double(s.used) / Double(s.limit))
    }
}

#Preview {
    let keyID = UUID()
    let stats = QuotaStats(apiKeyID: keyID, keyName: "Primary Key", limit: 10, used: 2, reserved: 2,
                           assignedSiteNames: ["East", "West"],
                           lastFetchTimestamp: Date().addingTimeInterval(-3600),
                           lastRefreshTimestamp: Date().addingTimeInterval(-1800),
                           nextAutoFetchTime: Date().addingTimeInterval(3600),
                           nextAutoRefreshTime: Date().addingTimeInterval(1800),
                           nextAutoRefreshIntervalMinutes: 30,
                           isKeyEnabled: true)
    APIUsageCard(quota: GlobalQuotaStats(perKey: [stats])).padding()
}
