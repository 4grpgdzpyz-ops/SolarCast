import SwiftUI

struct PVSitesSettingsCard: View {
    let sites: [PVSite]
    let onAddSite: () -> Void
    let onDelete: (UUID) -> Void

    private let rowHeight: CGFloat = 54

    var body: some View {
        SettingsCard(title: "PV Sites") {
            VStack(spacing: 0) {
                List {
                    ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                        let isFirst = index == 0
                        let isLast = index == sites.count - 1
                        NavigationLink(destination: PVSiteEditView(
                            viewModel: DIContainer.shared.makePVSiteEditViewModel(site: site))) {
                            HStack {
                                Circle().fill(site.color).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(site.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.scText)
                                    Text(site.solcastSiteID)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.scMuted)
                                }
                                // No manual chevron — NavigationLink adds one automatically
                            }
                            .padding(.top, isFirst ? 0 : 10)
                            .padding(.bottom, isLast ? 0 : 10)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        // Native separator instead of a manual Divider() —
                        // see APIKeysSettingsCard for the full reasoning.
                        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { onDelete(site.id) } label: {
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
                .contentMargins(.vertical, 0, for: .scrollContent)
                .frame(height: CGFloat(sites.count) * rowHeight)

                Button(action: onAddSite) {
                    Text("+ Add Site")
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
                // See APIKeysSettingsCard for the full reasoning — when
                // sites is empty, the List above contributes zero height,
                // so this must be 0 (not 12) to stay consistent with
                // SettingsBackupCard and a populated list's own
                // above-first-row gap.
                .padding(.top, sites.isEmpty ? 0 : 12)
            }
        }
    }
}
