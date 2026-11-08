import Foundation
import SwiftUI

/// First-run cold-account scan screen for subscriptions, paced against AO3.
struct ColdStartScanView: View {
    struct Progress: Equatable, Sendable {
        enum Phase: Equatable, Sendable { case idle, running, paused, finished }
        var phase: Phase = .idle
        var checked: Int = 0
        var total: Int = 0
        var username: String = ""
        /// Nil until enough pages have come back to estimate honestly.
        var remaining: Duration?

        init(
            phase: Phase = .idle,
            checked: Int = 0,
            total: Int = 0,
            username: String = "",
            remaining: Duration? = nil
        ) {
            self.phase = phase
            self.checked = checked
            self.total = total
            self.username = username
            self.remaining = remaining
        }
    }

    let progress: Progress
    var unavailableReason: String?
    var onStart: () -> Void = {}
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    var onCancel: () -> Void = {}
    var onChooseBackup: (() -> Void)?

    private var toGo: Int {
        max(0, progress.total - progress.checked)
    }

    /// Formatted status line showing checked count and honest rounded estimate.
    private var statusLineText: String {
        let count = "\(progress.checked) of \(progress.total)"
        if let remaining = progress.remaining,
           let estimate = Self.formatEstimate(remaining) {
            return "\(count) · \(estimate)"
        }
        return count
    }

    /// Deliberate identity copy: "Signed in as <username> · <total> follows · <checked> checked · <to go> to go".
    var identityText: String {
        var parts: [String] = []
        if !progress.username.isEmpty {
            parts.append("Signed in as \(progress.username)")
        }
        let follows = progress.total
        parts.append("\(follows) \(follows == 1 ? "follow" : "follows")")
        parts.append("\(progress.checked) checked")
        if toGo > 0 {
            parts.append("\(toGo) to go")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Form {
            Group {
                // A backup costs no requests, so offer it above the network-heavy scan.
                Section {
                    backupCard
                }

                Section {
                    scanCard
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("Scan AO3")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Restore from a backup first")
                    .font(.headline)
            }

            Text(
                "A Kudos backup already holds what each follow looked like, "
                + "so restoring one costs no requests at all."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            // shortcut: subscription-snapshot restore is disabled here, connect it when that driver lands
            Button("Choose a backup") { onChooseBackup?() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(onChooseBackup == nil)
        }
        .padding(.vertical, 4)
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Checking your subscriptions")
                    .font(.headline)
            }

            if let unavailableReason {
                Text(unavailableReason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView(
                    value: Double(progress.checked),
                    total: Double(max(progress.total, 1))
                )
                .tint(.accentColor)

                Text(statusLineText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Text(identityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if progress.phase == .running || progress.phase == .paused {
                Text(
                    "AO3 pages alphabetically, so what is checked so far is the start "
                    + "of the alphabet, not what changed most recently."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            actionButtons
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch progress.phase {
        case .idle:
            Button("Start", action: onStart)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(unavailableReason != nil)
        case .running:
            HStack(spacing: 12) {
                Button("Pause", action: onPause)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.primary)
                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.primary)
            }
        case .paused:
            HStack(spacing: 12) {
                Button("Resume", action: onResume)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.primary)
                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.primary)
            }
        case .finished:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Scan finished")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        }
    }

    /// Formats the honest estimate as RelativeDateTimeFormatter-style wording, rounding up to whole minutes.
    static func formatEstimate(_ duration: Duration) -> String? {
        let seconds = duration.components.seconds
        guard seconds > 0 || duration.components.attoseconds > 0 else { return nil }

        // Round up: any non-zero fraction of a minute increments the whole minute count.
        let hasFraction = (seconds % 60 > 0) || (duration.components.attoseconds > 0)
        let minutes = Int(seconds / 60) + (hasFraction ? 1 : 0)

        if minutes <= 1 {
            return "about a minute left"
        } else if minutes < 60 {
            return "about \(minutes) minutes left"
        } else {
            let hours = Int(ceil(Double(minutes) / 60.0))
            return hours == 1 ? "about an hour left" : "about \(hours) hours left"
        }
    }
}

#Preview("Idle") {
    NavigationStack {
        ColdStartScanView(
            progress: .init(phase: .idle, checked: 0, total: 35, username: "skydarius11")
        )
    }
    .environment(ThemeManager())
}

#Preview("Running (with estimate)") {
    NavigationStack {
        ColdStartScanView(
            progress: .init(
                phase: .running,
                checked: 12,
                total: 15,
                username: "skydarius11",
                remaining: .seconds(75)
            )
        )
    }
    .environment(ThemeManager())
}

#Preview("Running (without estimate)") {
    NavigationStack {
        ColdStartScanView(
            progress: .init(
                phase: .running,
                checked: 2,
                total: 15,
                username: "skydarius11",
                remaining: nil
            )
        )
    }
    .environment(ThemeManager())
}

#Preview("Paused") {
    NavigationStack {
        ColdStartScanView(
            progress: .init(
                phase: .paused,
                checked: 8,
                total: 15,
                username: "skydarius11",
                remaining: .seconds(180)
            )
        )
    }
    .environment(ThemeManager())
}

#Preview("Finished") {
    NavigationStack {
        ColdStartScanView(
            progress: .init(
                phase: .finished,
                checked: 15,
                total: 15,
                username: "skydarius11"
            )
        )
    }
    .environment(ThemeManager())
}
