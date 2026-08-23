import SwiftUI
struct ForecastSummaryCard: View {
    let stats: StatsResult
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current; return f }()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Forecast Summary").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.scText)
                .padding(.horizontal, 16).padding(.top, 13)
            Divider().padding(.top, 10)
            HStack(spacing: 0) {
                col(label: "AVERAGE", value: String(format: "%.2f", stats.averageKW), unit: "kW",
                    foot: "over \(stats.sunWindow.roundedHours) hours", align: .leading)
                Divider()
                col(label: "PEAK", value: String(format: "%.2f", stats.peakKW), unit: "kW",
                    foot: "at \(Self.fmt.string(from: stats.peakTimestamp))", align: .center)
                Divider()
                col(label: "TOTAL", value: String(format: "%.1f", stats.totalKWh), unit: "kWh",
                    foot: "production", align: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color.scCard).clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.scBorder, lineWidth: 1))
    }
    @ViewBuilder private func col(label: String, value: String, unit: String, foot: String, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.scAccent)
            (Text(value).font(.system(size: 18, weight: .bold)) + Text(" \(unit)").font(.system(size: 11)))
                .foregroundStyle(Color.scText)
            Text(foot).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.scAccent)
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : align == .trailing ? .trailing : .center)
        .padding(.horizontal, 14)
    }
}

#Preview {
    let sunrise = Date()
    let sunset = sunrise.addingTimeInterval(16 * 3600)
    let window = SunWindow(sunrise: sunrise, sunset: sunset)
    ForecastSummaryCard(stats: StatsResult(
        scenario: .normal, date: Date(), sunWindow: window,
        averageKW: 3.88, peakKW: 6.79, peakTimestamp: sunrise.addingTimeInterval(7 * 3600),
        totalKWh: 60.2, bestInterval: nil))
        .padding()
}
