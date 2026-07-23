import SwiftUI
struct BestIntervalCard: View {
    let interval: BestInterval
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("⚡ BEST TIME TO RUN APPLIANCES")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.scGreen).tracking(0.5)
            HStack(alignment: .center) {
                Text("\(Self.fmt.string(from: interval.start)) – \(Self.fmt.string(from: interval.end))")
                    .font(.system(size: 19, weight: .heavy)).foregroundStyle(Color.scText)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "~ %.1f kWh total", interval.totalKWh))
                    Text(String(format: "~ %.2f kW avg", interval.averageKW))
                }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.scAccent)
            }
            Text("Ideal for EV charging, dishwasher & washing machine")
                .font(.system(size: 11)).foregroundStyle(Color.scMuted)
        }
        .padding(14)
        .background(LinearGradient(colors: [Color.scAccent.opacity(0.12), Color.scGreen.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.scGreen.opacity(0.28), lineWidth: 1))
    }
}

#Preview {
    let now = Date()
    BestIntervalCard(interval: BestInterval(
        start: now.addingTimeInterval(7 * 3600),
        end: now.addingTimeInterval(9 * 3600),
        totalKWh: 13.5, averageKW: 6.74))
        .padding()
}
