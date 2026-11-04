import SwiftUI

/// What the "Kudos on this iPhone" bar is made of. Pure so the grouping is pinned
/// by tests: the bar's segments must add up to `LocalStorageFootprint.totalBytes`,
/// the same number Privacy and local data breaks down, so the two can never disagree.
enum StorageBreakdown {
    enum Kind: CaseIterable { case works, originals, other }

    struct Segment: Equatable, Identifiable {
        let kind: Kind
        let bytes: Int64
        var id: Kind { kind }

        var title: String {
            switch kind {
            case .works: "Downloads"
            case .originals: "Original files"
            case .other: "Fonts, cache"
            }
        }
    }

    /// Non-empty segments in display order. Downloads includes reading copies;
    /// "Fonts, cache" includes imported fonts, caches and draft recovery.
    static func segments(_ footprint: LocalStorageFootprint) -> [Segment] {
        [
            Segment(kind: .works, bytes: footprint.downloadedWorkBytes + footprint.readingCopyBytes),
            Segment(kind: .originals, bytes: footprint.preservedOriginalBytes),
            Segment(
                kind: .other,
                bytes: footprint.importedFontBytes + footprint.cacheBytes + footprint.draftRecoveryBytes
            )
        ].filter { $0.bytes > 0 }
    }
}

/// Board 50's "Kudos on this iPhone": the measured total, a stacked bar and a
/// legend. Replaces the old single "Storage used" row, which showed the same total.
struct StorageSummaryRow: View {
    @Environment(\.accentInk) private var accentInk
    @State private var footprint: LocalStorageFootprint?

    private func color(_ kind: StorageBreakdown.Kind) -> Color {
        switch kind {
        case .works: accentInk
        case .originals: .orange
        case .other: .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Kudos on this \(ThisDevice.name)") {
                if let footprint {
                    Text(LocalStorageFootprint.formatted(bytes: footprint.totalBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    // Measuring walks several directories, so say it is working
                    // rather than show a zero that is about to change.
                    ProgressView().controlSize(.small).accentFill()
                }
            }
            if let footprint {
                let segments = StorageBreakdown.segments(footprint)
                if !segments.isEmpty {
                    bar(segments)
                    legend(segments)
                }
            }
        }
        .task {
            if footprint == nil { footprint = await LocalDataFootprintScanner.measure() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kudos on this \(ThisDevice.name)")
        .accessibilityValue(accessibilityValue)
    }

    private func bar(_ segments: [StorageBreakdown.Segment]) -> some View {
        let total = Double(segments.reduce(Int64(0)) { $0 + $1.bytes })
        return GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    color(segment.kind)
                        .frame(width: max(2, proxy.size.width * Double(segment.bytes) / total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    /// One line when it fits, otherwise one item per line (never truncated).
    private func legend(_ segments: [StorageBreakdown.Segment]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { legendItems(segments) }
            VStack(alignment: .leading, spacing: 4) { legendItems(segments) }
        }
    }

    private func legendItems(_ segments: [StorageBreakdown.Segment]) -> some View {
        ForEach(segments) { segment in
            HStack(spacing: 4) {
                Circle().fill(color(segment.kind)).frame(width: 8, height: 8)
                Text("\(segment.title) \(LocalStorageFootprint.formatted(bytes: segment.bytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    private var accessibilityValue: String {
        guard let footprint else { return "Measuring" }
        let parts = StorageBreakdown.segments(footprint).map {
            "\($0.title) \(LocalStorageFootprint.formatted(bytes: $0.bytes))"
        }
        return ([LocalStorageFootprint.formatted(bytes: footprint.totalBytes)] + parts).joined(separator: ", ")
    }
}
