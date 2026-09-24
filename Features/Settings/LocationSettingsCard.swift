import SwiftUI
struct LocationSettingsCard: View {
    let location: UserLocation?; let onTap: () -> Void; var onDelete: (() -> Void)?
    // Was hardcoded to 46, which cropped the swipe-to-delete button — then
    // raised to 54 to match APIKeysSettingsCard/PVSitesSettingsCard's own
    // row height, which fixed the cropping but was never actually measured
    // against THIS row's own content, and ended up visibly oversized.
    // Settled on 48 via a red/green diagnostic border comparison (row
    // content vs. List's fixed frame): a good match for the row's own
    // content size. Worth noting for whoever touches this next — the
    // swipe-to-delete button appears to have its own iOS-enforced minimum
    // height, independent of this constant, so shrinking rowHeight further
    // to chase an even tighter content match risks the delete button
    // visually overflowing the row again, the same class of problem the
    // original 46->54 change was fixing. 48 was chosen as the settled
    // value with that tradeoff in mind, not as an exact content-only
    // measurement.
    private let rowHeight: CGFloat = 48

    var body: some View {
        SettingsCard(title: "Location") {
            VStack(spacing: 0) {
                if location != nil {
                    List {
                        Button(action: onTap) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location?.name ?? "")
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.scText)
                                    Text(String(format: "%.4f, %.4f", location?.latitude ?? 0, location?.longitude ?? 0))
                                        .font(.system(size: 11)).foregroundStyle(Color.scMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.scMuted)
                            }
                            // Location's list always has exactly one row —
                            // top 0, bottom 0, for both the list's own
                            // content margins and this single item's own
                            // padding, per direct instruction.
                            .padding(.vertical, 0)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { onDelete?() } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .scrollDisabled(true)
                    .listSectionSeparator(.hidden)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                    .frame(height: rowHeight)
                } else {
                    Button(action: onTap) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No location set")
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.scText)
                                Text("Used for sunrise/sunset calculation")
                                    .font(.system(size: 11)).foregroundStyle(Color.scMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.scMuted)
                        }
                    }
                }
            }
        }
    }
}
