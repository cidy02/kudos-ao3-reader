import SwiftUI

/// App-wide progress for a scan the user already started. Hidden once the scan
/// is idle or finished; leaving the Subscriptions screen does not stop it.
struct SubscriptionScanBanner: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(SubscriptionScanService.self) private var scan

    var body: some View {
        Group {
            switch scan.phase {
            case .running, .paused, .stopped:
                card
            case .idle, .finished:
                EmptyView()
            }
        }
        .animation(.snappy(duration: 0.25), value: scan.phase)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            if scan.total > 0 {
                ProgressView(value: Double(scan.checked), total: Double(scan.total))
                    .accentFill()
            }

            if let detailNote {
                Text(detailNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    private var headline: String {
        if scan.total == 0, scan.checked == 0, let note = scan.statusNote, !note.isEmpty {
            return note
        }
        return ColdStartScanView.statusLine(
            checked: scan.checked,
            total: scan.total,
            remaining: scan.remaining
        )
    }

    /// The headline already used the note when there is nothing to count yet.
    private var detailNote: String? {
        guard scan.total > 0 || scan.checked > 0 else { return nil }
        return scan.statusNote
    }

    @ViewBuilder
    private var controls: some View {
        switch scan.phase {
        case .running:
            buttonRow {
                Button("Pause") { scan.pause() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                Button("Cancel", role: .cancel) { scan.cancel() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
            }
        case .paused:
            buttonRow {
                Button("Resume") { scan.resume() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                Button("Cancel", role: .cancel) { scan.cancel() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
            }
        case .stopped:
            Button("Close") { scan.cancel() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
                .foregroundStyle(.primary)
        case .idle, .finished:
            EmptyView()
        }
    }

    /// Side by side normally; stacked at accessibility sizes so labels don't break
    /// mid-word. Neutral tint: the user's accent fails contrast on dark capsules.
    private func buttonRow(@ViewBuilder _ buttons: () -> some View) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout { buttons() }.foregroundStyle(.primary)
    }
}
