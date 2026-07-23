import SwiftUI
struct SiteBreakdownCard: View {
    let sites: [PVSite]; let chartSeries: [ChartSeries]

    private func totalKWh(for id: String) -> Double {
        // 0.5 hours per point — this app's real grid interval is 30
        // minutes (confirmed throughout ChartDataAssembler, the mock
        // generator, and the Solcast API's own PT30M period), not 15.
        // The previous 0.25 hardcoded a 15-minute assumption that doesn't
        // match anything else in this app, making every total here
        // exactly half of StatsEngine's correctly-computed totalKWh
        // (which derives its interval from the real period, not a
        // hardcoded guess) — a clean, systematic 2x error, not a vague
        // rounding difference.
        (chartSeries.first(where: { $0.id == id })?.points.reduce(0) { $0 + $1.kW * 0.5 }) ?? 0
    }
    private var grandTotal: Double { totalKWh(for: "total") }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily Breakdown").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.scText)
                .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 8)
            ForEach(sites) { site in
                let kwh = totalKWh(for: site.id.uuidString)
                let pct = grandTotal > 0 ? kwh / grandTotal * 100 : 0
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        HStack(spacing: 8) {
                            Circle().fill(site.color).frame(width: 10, height: 10)
                            Text(site.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.scText)
                        }
                        Spacer()
                        Text(String(format: "%.1f kWh", kwh)).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.scText)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.scSurfaceMuted)
                            RoundedRectangle(cornerRadius: 4).fill(site.color).frame(width: geo.size.width * pct / 100)
                        }
                    }.frame(height: 4)
                    Text(String(format: "%.0f%% of total", pct)).font(.system(size: 9)).foregroundStyle(Color.scMuted)
                }
                .padding(.horizontal, 16).padding(.vertical, 9).overlay(Divider(), alignment: .top)
            }
            HStack {
                Text("Total").font(.system(size: 14, weight: .bold))
                Spacer()
                Text(String(format: "%.1f kWh", grandTotal)).font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.scOrange).padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(Divider(), alignment: .top)
        }
        .background(Color.scCard).clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.scBorder, lineWidth: 1))
    }
}

#Preview {
    let sites = [
        PVSite(solcastSiteID: "pv_east", name: "East", colorHex: "#00C853"),
        PVSite(solcastSiteID: "pv_west", name: "West", colorHex: "#2196F3"),
    ]
    SiteBreakdownCard(sites: sites, chartSeries: []).padding()
}
