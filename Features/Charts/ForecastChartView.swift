import SwiftUI
import Charts

struct ForecastChartView: View {
    /// Single, real source of truth for the tooltip's fixed width —
    /// used both by the edge-aware placement logic and by
    /// tooltip(timestamp:)'s own frame.
    private static let tooltipWidth: Double = 130
    let series: [ChartSeries]
    let hiddenIDs: Set<String>
    let sunWindow: SunWindow?
    @Bindable var viewModel: ChartViewModel

    var visibleSeries: [ChartSeries] { series.filter { !hiddenIDs.contains($0.id) } }

    /// Reference timeline — all series share the same slots, one 30-minute
    /// sample apart. Sun sits at index 0 (the first sample), moon at the
    /// last index — no padding, no data plotted outside daylight.
    ///
    /// Reads from series (all lines), not visibleSeries — same principle
    /// as yMax being locked to the full data set. Previously this read
    /// visibleSeries.first, so hiding every line made visibleSeries empty,
    /// which collapsed timeline to [], slotCount to 0, and the X axis's
    /// own domain to a degenerate near-zero-width range — the entire X
    /// axis (positions, tick marks, time labels) disappeared rather than
    /// staying anchored to the real time slots. Locking to series means
    /// the X axis stays correctly positioned regardless of which lines
    /// are toggled, exactly like the Y axis fix.
    private var timeline: [ChartDataPoint] { series.first?.points ?? [] }
    private var slotCount: Int { timeline.count }

    /// Axis position IS the raw sample index — plain linear axis, one unit
    /// per 30-minute sample. No anchor chain, no stretching/compressing
    /// edge segments to force a fixed label-to-label spacing; every sample
    /// sits at its true relative position. This replaces an earlier
    /// anchor-chain design that forced every label exactly 8 units apart
    /// regardless of real elapsed time — that requirement is deliberately
    /// dropped here in favor of this simpler, directly-specified approach.
    private func axisPosition(forSlot index: Int) -> Double {
        Double(index)
    }

    /// Which sample indices get an hour label — every real sample whose
    /// timestamp lands exactly on a clock-aligned 4-hour mark (08:00,
    /// 12:00, 16:00, 20:00, ...). This replaces stride(by: 8) over the
    /// array index, which only happened to look correct when sunrise
    /// floored to an exact multiple-of-4 hour — in the general case (e.g.
    /// sunrise 05:36 -> first real slot 05:30) it drifted from real clock
    /// time (labeling index 8 as if it were 08:00, when the sample at
    /// index 8 is actually 09:30). Filtering the real timeline's
    /// timestamps directly means a label only ever appears at the
    /// position of the real data point matching that clock hour — never a
    /// wrong position for a right label, and never a right position with
    /// a wrong label. Sun (index 0) and moon (last index) are handled
    /// separately in the switch below, not part of this list.
    private var xAxisLabelIndices: [Int] {
        guard slotCount > 0 else { return [] }
        let cal = Calendar.current
        return timeline.indices.filter { i in
            let comps = cal.dateComponents([.hour, .minute], from: timeline[i].localTimestamp)
            return (comps.hour ?? -1) % 4 == 0 && comps.minute == 0
        }
    }

    /// Inverse of axisPosition(forSlot:) — trivial now that the axis is a
    /// plain linear index, but kept as a named function so chartXSelection's
    /// binding reads the same way regardless of how positioning works.
    private func nearestSlot(toAxisX x: Double) -> Int? {
        guard slotCount > 0 else { return nil }
        let idx = Int(x.rounded())
        return min(max(idx, 0), slotCount - 1)
    }

    /// Y-axis tick label text — a whole number if kW lands exactly on
    /// one, otherwise one decimal place. Plain, non-View function,
    /// computed entirely outside any SwiftUI closure — a ternary
    /// combining string interpolation and String(format:) directly
    /// inside Text(...) is a real, confirmed trigger for Swift's
    /// "unable to type-check in reasonable time" error; a genuine
    /// if/else statement here avoids it entirely.
    private func yAxisLabel(for kW: Double) -> String {
        if kW == kW.rounded() {
            return "\(Int(kW))"
        }
        return String(format: "%.1f", kW)
    }

    @ViewBuilder
    private func yAxisLabelView(for kW: Double) -> some View {
        Text(yAxisLabel(for: kW))
            .font(.system(size: 9))
            .foregroundStyle(Color.scMuted)
    }

    /// X-axis label — sun glyph at index 0, moon glyph at the last
    /// index, hour text otherwise. Extracted into its own @ViewBuilder
    /// function — a switch with three differently-typed branches
    /// inside AxisValueLabel inside AxisMarks is the same real class of
    /// accumulated-closure-complexity risk as the y-axis label above.
    @ViewBuilder
    private func xAxisLabelView(forIndex index: Int) -> some View {
        switch index {
        case 0:
            Image(systemName: "sun.max.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.scAmber)
        case slotCount - 1:
            Image(systemName: "moon.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.scMoon)
                .scaleEffect(x: -1, y: 1)
        default:
            if index < timeline.count {
                Text(timeline[index].localTimestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 9))
                    .foregroundStyle(Color.scMuted)
            }
        }
    }

    /// Named struct rather than a tuple. Swift's type checker has to unify
    /// every field of an anonymous tuple simultaneously when it appears
    /// inside a ForEach/LineMark chain, and a 5-field tuple here is enough to
    /// trip the "unable to type-check in reasonable time" error. A named
    /// type lets the compiler resolve each usage independently.
    private struct PlotPoint: Identifiable {
        let id: String
        let name: String
        let color: Color
        let x: Double
        let kW: Double
    }

    /// Named struct rather than a tuple, for the same real reason as
    /// PlotPoint above — an anonymous tuple here is enough to trip
    /// Swift's type-checker once used inside multiple ForEach/closure
    /// chains throughout body.
    private struct SelectedValue: Identifiable {
        var id: String { seriesID }
        let seriesID: String
        let name: String
        let color: Color
        let kW: Double
    }

    private var plotPoints: [PlotPoint] {
        visibleSeries.flatMap { s in
            s.points.enumerated().map { i, p in
                PlotPoint(id: p.id, name: s.name, color: Color(hex: s.colorHex),
                          x: axisPosition(forSlot: i), kW: p.kW)
            }
        }
    }

    private var yMax: Double {
        // Locked to the peak across ALL series, not just visibleSeries —
        // deliberately independent of which lines are currently toggled
        // on. Using visibleSeries here would rescale the axis every time
        // a line is hidden or shown (shrinking when a tall line is
        // hidden, growing back when it's shown again), which makes it
        // hard to visually compare a line's shape before/after toggling
        // others. Locking to the full data set means hiding/showing
        // lines only changes what's drawn, never moves the axis.
        let peak = series.flatMap { $0.points }.map(\.kW).max() ?? 2
        return max(2, (peak / 0.5).rounded(.up) * 0.5 + 0.5)
    }

    /// Currently selected slot (a real 30-min sample index, 0..<slotCount).
    private var selectedIndex: Int? {
        guard let idx = viewModel.activeIndex, idx >= 0, idx < slotCount else { return nil }
        return idx
    }

    /// The same selection, expressed on the axis's position scale.
    private var selectedX: Double? {
        guard let idx = selectedIndex else { return nil }
        return axisPosition(forSlot: idx)
    }

    private var selectedTimestamp: Date? {
        guard let idx = selectedIndex else { return nil }
        return timeline[idx].localTimestamp
    }

    /// kW of every visible series at the selected slot — drives the dots and tooltip.
    private var selectedValues: [SelectedValue] {
        guard let idx = selectedIndex else { return [] }
        return visibleSeries.compactMap { s in
            guard idx < s.points.count else { return nil }
            return SelectedValue(seriesID: s.id, name: s.name, color: Color(hex: s.colorHex), kW: s.points[idx].kW)
        }
    }

    /// The main forecast lines — one per visible series. Extracted into
    /// its own, separately-typed piece so the Chart body doesn't have to
    /// infer this ForEach's full type simultaneously alongside
    /// selectionOverlay's own content.
    @ChartContentBuilder
    private var forecastLines: some ChartContent {
        ForEach(plotPoints, id: \.id) { item in
            LineMark(
                x: .value("Position", item.x),
                y: .value("kW", item.kW),
                series: .value("Site", item.name)
            )
            .foregroundStyle(item.color)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
    }

    /// The selected-slot rule line, plus one highlighted point per
    /// visible series at that slot. Extracted for the same real reason
    /// as forecastLines above.
    @ChartContentBuilder
    private var selectionOverlay: some ChartContent {
        if let x = selectedX {
            RuleMark(x: .value("Selected", x))
                .foregroundStyle(Color.scMuted.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            ForEach(selectedValues, id: \.seriesID) { sel in
                PointMark(
                    x: .value("Position", x),
                    y: .value("kW", sel.kW)
                )
                .symbolSize(60)
                .foregroundStyle(sel.color)
            }
        }
    }

    var body: some View {
        Chart {
            forecastLines
            selectionOverlay
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...yMax)
        // Symmetric, small margin on both sides — this is what actually
        // makes both sun (at index 0) and moon (at the last index) visible
        // without being clipped by the plot frame. Replaces an earlier
        // asymmetric domain (0 on the left, +1.5 on the right) that was
        // tuned to compensate for a labeling bug rather than fixing the
        // real cause.
        .chartXScale(domain: -0.1...(Double(max(slotCount - 1, 0)) + 0.1))
        .chartXAxis {
            // Sun, every 4-hour label, and moon are all entries in ONE mark
            // list — every mark gets the identical AxisGridLine + AxisTick +
            // AxisValueLabel treatment, with the label's CONTENT chosen
            // inside xAxisLabelView.
            let markIndices: [Int] = {
                guard slotCount > 0 else { return [] }
                var idxs = Set(xAxisLabelIndices)
                idxs.insert(0)
                idxs.insert(slotCount - 1)
                return idxs.sorted()
            }()
            AxisMarks(values: markIndices) { value in
                let index = value.as(Int.self) ?? 0
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(Color.scGridLine.opacity(0.9))
                AxisTick()
                AxisValueLabel(anchor: .top) {
                    xAxisLabelView(forIndex: index)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(Color.scGridLine.opacity(0.9))
                AxisValueLabel(horizontalSpacing: 6) {
                    if let kW = value.as(Double.self) {
                        yAxisLabelView(for: kW)
                    }
                }
            }
        }
        // Native selection: taps and horizontal scrubs land here, while
        // vertical drags fall through to the enclosing ScrollView.
        .chartXSelection(value: Binding(
            get: { selectedX },
            set: { newX in
                guard let newX, let idx = nearestSlot(toAxisX: newX) else { return }
                viewModel.handleTap(at: idx)
            }
        ))
        .chartOverlay { proxy in
            GeometryReader { geo in
                tooltipPlacement(proxy: proxy, geo: geo)
            }
        }
        .padding(.bottom, 0)
    }

    /// The actual tooltip placement — kept as its own, separately-typed
    /// function from the start (not written inline inside
    /// .chartOverlay/GeometryReader), taking proxy/geo as real, explicit
    /// parameters. Per direct spec: 30pt leading/trailing from the
    /// selected point's real, actual screen position, flipping sides
    /// when that would overflow the plot area's real width; 10pt fixed
    /// from the chart's top, no vertical flip.
    @ViewBuilder
    private func tooltipPlacement(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if !selectedValues.isEmpty, let ts = selectedTimestamp, let x = selectedX,
           // +1.0 correction — confirmed via direct, real debug-marker
           // evidence that ChartProxy.position(forX:) consistently
           // returns a screen position exactly one data-point slot to
           // the LEFT of the actual, real rendered position of the
           // selected point (the same real x value used here also
           // drives the real PointMark/RuleMark the chart itself
           // draws — those are correct; position(forX:)'s own
           // conversion is what's off, consistently, by exactly one
           // slot). The axis is a plain linear index at 1.0 per
           // 30-minute slot (confirmed via axisPosition(forSlot:)), so
           // +1.0 is a real, direct, measured correction, not a guess.
           let anchorXRaw = proxy.position(forX: x + 1.0) {
            let anchorX = Double(anchorXRaw)
            let tooltipWidth = Self.tooltipWidth
            let horizontalOffset: Double = 30
            let topPadding: Double = 10
            // Would placing the tooltip on the TRAILING side (its own
            // leading edge at anchorX + offset) push its trailing edge
            // past the plot area's real, actual right bound? If so,
            // flip to the LEADING side instead (tooltip's trailing edge
            // at anchorX - offset, i.e. its leading edge at
            // anchorX - offset - tooltipWidth).
            let wouldOverflowTrailing = anchorX + horizontalOffset + tooltipWidth > Double(geo.size.width)
            let tooltipLeadingX = wouldOverflowTrailing
                ? anchorX - horizontalOffset - tooltipWidth
                : anchorX + horizontalOffset

            // .overlay(alignment: .topLeading) places the tooltip's own
            // top-left corner at (0, 0) within this GeometryReader's
            // frame — .offset then moves that SAME corner by the given
            // delta, correctly landing it at the real, desired screen
            // position without needing to know the tooltip's own actual
            // size at all (unlike .position(x:y:), which places a
            // view's CENTER, not its corner).
            Color.clear
                .overlay(alignment: .topLeading) {
                    tooltip(timestamp: ts)
                        .offset(x: CGFloat(tooltipLeadingX), y: CGFloat(topPadding))
                }
        }
    }

    // MARK: - Tooltip

    private func tooltip(timestamp: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.scText)
            ForEach(selectedValues, id: \.seriesID) { row in
                HStack(spacing: 5) {
                    Circle().fill(row.color).frame(width: 6, height: 6)
                    Text(row.name)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.scMuted)
                    Spacer(minLength: 6)
                    Text(String(format: "%.2f kW", row.kW))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.scText)
                }
                if row.seriesID == "total" {
                    Divider()
                }
            }
        }
        .padding(8)
        .frame(width: Self.tooltipWidth, alignment: .leading)
        .background(Color.scCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.scBorder, lineWidth: 1))
        .shadow(radius: 4)
    }
}
