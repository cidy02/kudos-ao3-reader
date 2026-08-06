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
            Form {
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
            .formStyle(.grouped)
            .appThemedScroll()
            .navigationTitle("Check Availability")
            .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isRunning ? "Stop" : "Done") {
                        if isRunning {
                            task?.cancel()
                        } else {
                            dismiss()
                        }
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
                Text("Kudos will ask AO3 about \(pendingCount.formatted()) "
                    + "\(pendingCount == 1 ? "work" : "works"), one at a time.")
                    .font(.subheadline)
                // The honest reason this is a button and not a background task.
                Text("There is no way to ask AO3 what changed, so this is one request per "
                    + "work. It runs slowly on purpose — about two seconds each — to stay "
                    + "well inside what a person browsing the site would do. You can stop "
                    + "it at any time and keep whatever it has already found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if unverifiableCount > 0 {
                    Text("\(unverifiableCount.formatted()) imported "
                        + "\(unverifiableCount == 1 ? "work is" : "works are") from other sites and "
                        + "can't be checked — Kudos has no way to reach them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if pendingCount > WorkAvailabilitySweep.defaultLimit {
                    Text("This run will cover \(WorkAvailabilitySweep.defaultLimit) of them. "
                        + "Run it again later for the rest — already-checked works are skipped "
                        + "for a week.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .cardRow()
        } header: {
            Text("What this does")
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
                    Text("Your downloaded copies are now marked as the last copy, and are kept "
                        + "permanently.")
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
            parts.append("\(summary.remaining.formatted()) still to check — run this again to continue.")
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
            if pendingCount == 0 {
                Text("Every AO3 work in your Library was checked within the last week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
