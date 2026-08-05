import SwiftUI

struct APIKeysSettingsCard: View {
    let apiKeys: [APIKey]
    let sites: [PVSite]
    let onToggleEnabled: (UUID) -> Void
    let onAddKey: () -> Void
    let onDelete: (UUID) -> Void

    private let rowHeight: CGFloat = 54

    var body: some View {
        SettingsCard(title: "API Keys") {
            VStack(spacing: 0) {
                List {
                    ForEach(Array(apiKeys.enumerated()), id: \.element.id) { index, key in
                        let isFirst = index == 0
                        let isLast = index == apiKeys.count - 1
                        NavigationLink(destination: APIKeyEditView(
                            viewModel: DIContainer.shared.makeAPIKeyEditViewModel(key: key))) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(key.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.scText)
                                    if !key.isEnabled {
                                        Text("DISABLED")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.scRed.opacity(0.15))
                                            .foregroundStyle(Color.scRed)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                let count = key.assignedSiteIDs.count
                                Text("\(count) site\(count == 1 ? "" : "s") · limit \(key.hasUnlimitedQuota ? "unlimited" : "\(key.dailyQuotaLimit)/day")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.scMuted)
                            }
                            // First row: no top padding. Last row: no
                            // bottom padding. A single row is both first
                            // and last, so it gets neither — flush on
                            // both edges, matching the card's own outer
                            // padding rather than adding extra space on
                            // top of it.
                            .padding(.top, isFirst ? 0 : 10)
                            .padding(.bottom, isLast ? 0 : 10)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        // Native separator instead of a manual Divider() —
                        // edges: .bottom restricts it to the bottom of
                        // each row only (the default is all edges, which
                        // would show a separator on both top and bottom
                        // of every row — two overlapping lines between
                        // adjacent rows). Hidden for the last row, since
                        // there's nothing below it to separate from.
                        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { onDelete(key.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDisabled(true)
                .listSectionSeparator(.hidden)
                // List reserves its own outer vertical content margin,
                // separate from per-row insets — zeroing listRowInsets alone
                // does not remove this. This is the actual source of the
                // "extra space above the first / below the last row" that
                // .listRowInsets couldn't fix.
                .contentMargins(.vertical, 0, for: .scrollContent)
                .frame(height: CGFloat(apiKeys.count) * rowHeight)

                Button(action: onAddKey) {
                    Text("+ Add API Key")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.scAccent)
                        .background(Color.scAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.scAccent,
                                          style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                // When apiKeys is empty, the List above contributes ZERO
                // height (frame(height: CGFloat(0) * rowHeight) == 0), so
                // an unconditional 12pt here would stack on top of
                // SettingsCard's own 12pt title-to-content gap, producing
                // 24pt total between "API KEYS" and this button — double
                // what SettingsBackupCard (12pt, no List involved at all)
                // and a POPULATED list's gap above its own first row
                // (also just SettingsCard's 12pt) actually have. Zero
                // extra padding in the empty case keeps all three
                // consistent at this specific gap.
                .padding(.top, apiKeys.isEmpty ? 0 : 12)
            }
        }
    }
}
