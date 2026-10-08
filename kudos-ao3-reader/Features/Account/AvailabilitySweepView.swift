import SwiftData
import SwiftUI

/// Manual "which of my works has AO3 deleted?" check.
///
/// The screen's job is to state the cost **before** any traffic is sent. A sweep is one
/// AO3 request per work, and the user is the only one who can decide that is worth it —
/// see `WorkAvailabilitySweep` for why this is deliberately not automatic.
struct AvailabilitySweepView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var pendingCount = 0
    @State private var unverifiableCount = 0
    @State private var completed = 0
    @State private var total = 0
    @State private var summary: WorkAvailabilitySweep.Summary?
    @State private var task: Task<Void, Never>?
    @State private var unavailableWorks: [SavedWork] = []

    private var isRunning: Bool { task != nil }

    var body: some View {
        NavigationStack {
            List {
                explanationSection
                if isRunning {
                    progressSection
                } else if let summary {
                    resultSection(summary)
                }
                if !unavailableWorks.isEmpty {
                    unavailableWorksSection
                }
                actionSection
            }
            .cardList()
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("Check Availability")
            .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
            .toolbar {
                // Stop interrupts on the leading edge; Done closes from the
                // trailing one, as every other sheet's confirmation does.
                if isRunning {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Stop") { task?.cancel() }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onAppear(perform: refreshCounts)
            .onDisappear { task?.cancel() }
        }
        .tint(theme.effectiveTint)
    }

    /// Every work currently marked unavailable, not just the ones this run found —
    /// the count alone (existing `resultSection`) doesn't say *which* works, and
    /// that persists across runs since `ao3Unavailable` is a durable flag.
    private var unavailableWorksSection: some View {
        Section {
            ForEach(unavailableWorks) { work in
                if gate.isHidden(work, enabled: hideMature, mode: matureMode)
                    || gate.isBlurred(work, enabled: hideMature, mode: matureMode) {
                    // This list named every mature work that had left AO3, with Hide or Blur
                    // on (audit A19-9). The row reveals, as a blurred row does anywhere else.
                    Button {
                        gate.reveal(work)
                    } label: {
                        Text("Hidden mature work")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hidden mature work. Activate to reveal.")
                    .cardRow()
                } else {
                    NavigationLink(value: work) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(work.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(work.author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .cardRow()
                }
            }
        } header: {
            Text("No longer on AO3 (\(unavailableWorks.count.formatted()))")
        }
    }

    private var explanationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kudos will check \(pendingCount.formatted()) "
                    + "\(pendingCount == 1 ? "work" : "works"), one at a time.")
                    .font(.subheadline)
                // The honest reason this is a button and not a background task.
                Text("AO3 can't tell Kudos what changed, so each work must be checked "
                    + "separately. Kudos waits about two seconds between works to avoid "
                    + "overloading AO3; you can stop anytime and keep the results so far.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if unverifiableCount > 0 {
                    Text("\(unverifiableCount.formatted()) imported "
                        + "\(unverifiableCount == 1 ? "work came" : "works came") from other sites, "
                        + "so Kudos can't check them on AO3.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if pendingCount > WorkAvailabilitySweep.defaultLimit {
                    Text("This check covers up to \(WorkAvailabilitySweep.defaultLimit) works. "
                        + "Start it again later for the rest; works checked during the past week "
                        + "are skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .cardRow()
        } header: {
            Text("Before you start")
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                Text("Checked \(completed.formatted()) of \(total.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .cardRow()
        }
    }

    private func resultSection(_ summary: WorkAvailabilitySweep.Summary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if summary.nowUnavailable > 0 {
                    Label("\(summary.nowUnavailable.formatted()) "
                        + "\(summary.nowUnavailable == 1 ? "work is" : "works are") no longer on AO3",
                        systemImage: "archivebox.fill")
                        .font(.subheadline)
                    Text("Kudos marked them as no longer on AO3. Any downloaded copies are now "
                        + "treated as the last copies you have and will be kept permanently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if summary.checked > 0 {
                    Label("Everything checked is still on AO3", systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
                Text(detailLine(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .cardRow()
        } header: {
            Text(summary.cancelled ? "Stopped" : "Finished")
        }
    }

    /// Says what was *not* done as plainly as what was — a sweep that quietly covered
    /// half the library would read as a clean bill of health.
    private func detailLine(_ summary: WorkAvailabilitySweep.Summary) -> String {
        var parts = ["Checked \(summary.checked.formatted())."]
        if summary.skippedRecent > 0 {
            parts.append("Skipped \(summary.skippedRecent.formatted()) checked in the last week.")
        }
        if summary.remaining > 0 {
            parts.append("\(summary.remaining.formatted()) still to check. Run this again to continue.")
        }
        return parts.joined(separator: " ")
    }

    private var actionSection: some View {
        Section {
            Button {
                start()
            } label: {
                Label(isRunning ? "Checking…" : "Check Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isRunning || pendingCount == 0)
            .cardRow()
            if pendingCount == 0 {
                Text("You checked every AO3 work in your Library within the past week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .cardRow()
            }
        }
    }

    private func refreshCounts() {
        pendingCount = WorkAvailabilitySweep.pending(in: context).count
        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        unverifiableCount = works.filter { !$0.isPendingDeletion && !$0.origin.supportsLiveLookup }.count
        unavailableWorks = works
            .filter { $0.ao3Unavailable && !$0.isPendingDeletion }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func start() {
        summary = nil
        completed = 0
        total = min(pendingCount, WorkAvailabilitySweep.defaultLimit)
        task = Task { @MainActor in
            let result = await WorkAvailabilitySweep.run(in: context) { done, count in
                completed = done
                total = count
            }
            summary = result
            task = nil
            refreshCounts()
        }
    }
}
