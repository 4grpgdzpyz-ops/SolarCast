import SwiftUI

struct ChartLegendPills: View {
    let series: [ChartSeries]
    let hiddenIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        // Use FlowLayout-style wrapping for multiple sites
        let rows = layoutRows(maxWidth: UIScreen.main.bounds.width - 60)
        VStack(spacing: 6) {
            ForEach(0..<rows.count, id: \.self) { rowIdx in
                HStack(spacing: 8) {
                    ForEach(rows[rowIdx], id: \.id) { s in
                        pillButton(s)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pillButton(_ s: ChartSeries) -> some View {
        let hidden = hiddenIDs.contains(s.id)
        return Button { onToggle(s.id) } label: {
            HStack(spacing: 6) {
                ZStack {
                    Capsule()
                        .fill(hidden ? Color.scSurfaceMuted : Color(hex: s.colorHex).opacity(0.25))
                        .frame(width: 26, height: 14)
                    Circle()
                        .fill(Color(hex: s.colorHex))
                        .frame(width: 10, height: 10)
                        .offset(x: hidden ? -5 : 5)
                }
                Text(s.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hidden ? Color.scMuted : Color.scText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(hidden ? Color.scSurfaceMuted.opacity(0.4) : Color.scSurfaceMuted))
            .overlay(Capsule().stroke(hidden ? Color.scBorder.opacity(0.2) : Color(hex: s.colorHex).opacity(0.4), lineWidth: 1))
            .opacity(hidden ? 0.6 : 1)
        }
    }

    /// Simple row layout: fills rows left-to-right, wraps when width exceeds max
    private func layoutRows(maxWidth: CGFloat) -> [[ChartSeries]] {
        var rows: [[ChartSeries]] = [[]]
        var currentWidth: CGFloat = 0
        let pillWidth: CGFloat = 110 // approximate pill width

        for s in series {
            if currentWidth + pillWidth > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(s)
            currentWidth += pillWidth
        }
        return rows
    }
}
