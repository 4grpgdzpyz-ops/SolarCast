import SwiftUI

struct ForecastChartCard: View {
    let series: [ChartSeries]
    @Binding var hiddenIDs: Set<String>
    let sunWindow: SunWindow?
    let onToggleSeries: (String) -> Void
    @State private var isFullScreen = false
    @State private var chartVM = ChartViewModel()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: title + sunrise/sunset + fullscreen icon
            HStack {
                Text("Forecast Chart")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.scText)
                Spacer()
                // Sunrise/sunset time — same symbols and colors already
                // used on the chart's own X axis (sun.max.fill / scAmber
                // for sunrise, moon.fill / scMoon with its horizontal
                // mirror for sunset), so this reads as the same sun/moon
                // shown on the axis, not a different visual language.
                // Two Spacer()s (one before, one after) genuinely center
                // this group in the space between the title and the
                // fullscreen icon, rather than pushing it flush against
                // the icon the way a single Spacer() did.
                if let sunWindow {
                    HStack(spacing: 24) {
                        HStack(spacing: 4) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.scAmber)
                            Text(Self.timeFmt.string(from: sunWindow.sunrise))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.scMuted)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.scMoon)
                                .scaleEffect(x: -1, y: 1)
                            Text(Self.timeFmt.string(from: sunWindow.sunset))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.scMuted)
                        }
                    }
                }
                Spacer()
                Button {
                    // 1. Update what the app says it supports
                    AppDelegate.allowedOrientations = .landscape
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first(where: { $0.isKeyWindow }),
                       let rootController = window.rootViewController {
                        // 2. Tell UIKit to re-evaluate the supported
                        // orientations — the real, current,
                        // non-deprecated instance method, called on the
                        // real, actual controller whose constraints
                        // just changed.
                        rootController.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                    // 3. Request the geometry/orientation change — the
                    // completion closure here only logs a real failure,
                    // it no longer triggers presentation itself.
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                            appLog("ForecastChartCard: requestGeometryUpdate failed: \(error)", level: .error)
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFullScreen = true
                    }
                } label: {
                    Image(systemName: "arrow.up.right.and.arrow.down.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.scMuted)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)

            // Matches the same title-to-divider spacing already
            // established in ForecastSummaryCard (Divider().padding(.top,
            // 10)) — this card was the one real outlier missing it. The
            // divider's own top padding is the ONLY source of this gap
            // (matching that same real pattern exactly), not stacked on
            // top of a separate bottom padding on the header itself,
            // which would have produced a 20pt gap instead of 10pt.
            Divider().padding(.top, 10)

            // Chart
            ForecastChartView(series: series, hiddenIDs: hiddenIDs,
                              sunWindow: sunWindow, viewModel: chartVM)
                .frame(height: 220)
                .padding(.horizontal, 14)

            // Pill legend — tappable toggles
            ChartLegendPills(series: series, hiddenIDs: hiddenIDs, onToggle: onToggleSeries)
                .padding(.vertical, 10)
        }
        .background(Color.scCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.scBorder, lineWidth: 1))
        .fullScreenCover(isPresented: $isFullScreen) {
            FullScreenChartView(series: series, hiddenIDs: $hiddenIDs,
                                sunWindow: sunWindow, onToggleSeries: onToggleSeries,
                                onDismiss: {
                                    AppDelegate.allowedOrientations = .portrait
                                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let window = scene.windows.first(where: { $0.isKeyWindow }),
                                       let rootController = window.rootViewController {
                                        rootController.setNeedsUpdateOfSupportedInterfaceOrientations()
                                    }
                                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                                            appLog("ForecastChartCard.onDismiss: requestGeometryUpdate failed: \(error)", level: .error)
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isFullScreen = false
                                    }
                                })
        }
    }
}

// MARK: - Fullscreen landscape chart

struct FullScreenChartView: View {
    let series: [ChartSeries]
    @Binding var hiddenIDs: Set<String>
    let sunWindow: SunWindow?
    let onToggleSeries: (String) -> Void
    let onDismiss: () -> Void
    @State private var chartVM = ChartViewModel()

    var body: some View {
        ZStack {
            Color.scBackground
            VStack(spacing: 0) {
                // Chart fills available space
                ForecastChartView(series: series, hiddenIDs: hiddenIDs,
                                  sunWindow: sunWindow, viewModel: chartVM)
                    .padding(.horizontal, 8)

                // Legend
                ChartLegendPills(series: series, hiddenIDs: hiddenIDs, onToggle: onToggleSeries)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .padding(.top, 24)
            .padding(.bottom, 21)
            .padding(.horizontal, 60)

            // Close button — a genuinely separate, floating element, matching
            // the real, standard pattern Notes' own compose button uses:
            // independent of the content's own internal spacing, positioned
            // directly against the outer container's own edges.
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.scMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 24)
            .padding(.trailing, 30)
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
    }
}

