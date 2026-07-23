import SwiftUI

/// Merged date-navigation + scenario-picker card — previously two separate
/// cards (DateNavigatorView + ScenarioBarView), each with their own
/// identical chrome (padding(16), scCard background, cornerRadius 16,
/// scBorder stroke). Combined into one card per direct instruction, with
/// the standalone "SCENARIO" label removed and a Divider (same pattern
/// already used elsewhere for multi-section cards, e.g.
/// DeveloperSettingsCard, SettingsBackupCard) separating the two rows.
/// cornerRadius was subsequently bumped from 16 to 20 to match the
/// dominant Dashboard convention (APIUsageCard, BestIntervalCard,
/// ForecastSummaryCard, SiteBreakdownCard all use 20) — this card was the
/// actual outlier, not the rest of the screen.
struct DateNavigatorView: View {
    let date: Date; let isToday: Bool
    let hasPreviousData: Bool
    let hasNextData: Bool
    let onPrevious: () -> Void; let onNext: () -> Void; let onTapTitle: () -> Void
    let selectedScenario: Scenario
    let onSelectScenario: (Scenario) -> Void
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d, yyyy"; return f }()

    private var isFuture: Bool {
        Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date())
    }

    private var subtitle: String {
        if isToday { return "Today · Live" }
        if isFuture { return "Forecast · Tap to change" }
        return "Historical · Tap to change"
    }

    var body: some View {
        // spacing: 12 matches SettingsCard's own internal VStack spacing
        // and ScenarioBarView's former spacing — the established
        // convention for vertical rhythm between sections within one card
        // of this chrome family, kept consistent rather than introducing
        // a new value.
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                        .background(Color.scSurfaceMuted)
                        .clipShape(Circle())
                }
                .disabled(!hasPreviousData)
                .opacity(!hasPreviousData ? 0.4 : 1)
                Spacer()
                Button(action: onTapTitle) {
                    VStack(spacing: 1) {
                        Text(Self.fmt.string(from: date)).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.scText)
                        Text(subtitle)
                            .font(.system(size: 11)).foregroundStyle(Color.scAccent)
                    }
                }
                Spacer()
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                        .background(Color.scSurfaceMuted)
                        .clipShape(Circle())
                }
                .disabled(!hasNextData)
                .opacity(!hasNextData ? 0.4 : 1)
            }

            Divider()

            Picker("Scenario", selection: Binding(
                get: { selectedScenario },
                set: { onSelectScenario($0) }
            )) {
                ForEach(Scenario.allCases) { scenario in
                    Text(scenario.displayName).tag(scenario)
                }
            }
            .pickerStyle(.segmented)
            // +2pt: the segmented control's own intrinsic chrome makes the
            // 12pt VStack gap above it look smaller than the identical
            // 12pt gap between the HStack and the divider — this
            // compensates visually, even though the underlying layout
            // spacing is otherwise symmetric.
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color.scCard).clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.scBorder, lineWidth: 1))
    }
}
