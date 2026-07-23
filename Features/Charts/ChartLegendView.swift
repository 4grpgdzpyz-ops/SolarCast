import SwiftUI
struct ChartLegendView: View {
    let series: [ChartSeries]; let hiddenIDs: Set<String>; let onToggle: (String) -> Void
    var body: some View {
        HStack(spacing: 12) {
            ForEach(series) { s in
                let isHidden = hiddenIDs.contains(s.id)
                Button { onToggle(s.id) } label: {
                    HStack(spacing: 5) {
                        Rectangle().fill(Color(hex: s.colorHex))
                            .frame(width: s.id == "total" ? 18 : 12, height: s.id == "total" ? 2.5 : 2)
                            .clipShape(Capsule())
                        Text(s.name)
                            .font(.system(size: 10, weight: s.id == "total" ? .bold : .regular))
                            .strikethrough(isHidden).foregroundStyle(Color.scMuted)
                    }
                }.opacity(isHidden ? 0.3 : 1)
            }
        }.frame(maxWidth: .infinity)
    }
}
