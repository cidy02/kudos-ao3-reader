import SwiftUI

/// Explains the ranked sources Kudos can use to learn what changed in a subscription.
struct UpdateSourcesView: View {
    var body: some View {
        Form {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where updates come from")
                            .font(.title2.bold())
                        Text("AO3's own subscriptions page lists what you follow, "
                            + "but never says what changed or when. These add that back. "
                            + "All three work; the first needs nothing from you.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    UpdateSourceCard(
                        rank: 1,
                        title: "Mail",
                        systemImage: "envelope",
                        benefit: "Exact times, chapter numbers, and word counts.",
                        cost: "No AO3 requests.",
                        detail: "Kudos reads mail only to find AO3's notifications. "
                            + "Nothing is uploaded, and nothing leaves this device.",
                        actionTitle: "Connect Mail"
                    )
                }

                Section {
                    UpdateSourceCard(
                        rank: 2,
                        title: "Scanning AO3",
                        systemImage: "magnifyingglass",
                        benefit: "Checks every follow directly against AO3.",
                        cost: "Slower; uses paged, paced AO3 requests.",
                        actionTitle: "Scan AO3"
                    )
                }

                Section {
                    UpdateSourceCard(
                        rank: 3,
                        title: "Restore from a backup",
                        systemImage: "archivebox",
                        benefit: "A Kudos backup already holds what each follow looked like, "
                            + "so restoring one costs no requests at all.",
                        cost: "No AO3 requests.",
                        actionTitle: "Choose a Backup"
                    )
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("Updates")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct UpdateSourceCard: View {
    let rank: Int
    let title: String
    let systemImage: String
    let benefit: String
    let cost: String
    var detail: String?
    let actionTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rank). \(title)")

            Text(benefit)
                .fixedSize(horizontal: false, vertical: true)

            Text("Cost: \(cost)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // shortcut: Setup destinations do not exist yet; enable these actions when they land.
            Button(actionTitle) {}
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        }
        .padding(.vertical, 4)
    }
}
