import SwiftData
import SwiftUI

// Settings › Downloads & Storage (Downloads, Preservation, Reading Queues) and
// Settings › Library & Sync › Library. Sections moved as-is from the old single
// page; the keys are the same `@AppStorage` keys the rest of the app reads.

struct SettingsDownloadsPage: View {
    /// 1ab's Downloads toggle. Read at the one place a subscribe can turn
    /// into a download — `WorkDetailView.downloadIfSubscribedWithoutEPUB`.
    @AppStorage("downloadOnSubscribe") private var downloadOnSubscribe = false
    /// Read where a work opens in the reader (`WorkLifecycle.keepIfKeepingWorksYouRead`).
    @AppStorage(WorkLifecycle.keepsWorksYouReadKey) private var keepsWorksYouRead = false

    var body: some View {
        SettingsPageForm(route: .downloads) {
            Section {
                Toggle("Keep works you read", isOn: $keepsWorksYouRead)
            } footer: {
                Text("When this is on, every work you open stays downloaded, as if you tapped "
                    + "Download. When it's off, finishing a work removes its copy unless you "
                    + "downloaded, favorited, or queued it. It stays in your history, and you "
                    + "can download it again.")
            }
            Section {
                Toggle("Download on subscribe", isOn: $downloadOnSubscribe)
                StorageUsedRow()
            } footer: {
                Text("When you subscribe to a work already in your Library, Kudos downloads it "
                    + "if no copy is stored. Privacy and Local Data shows what uses space and "
                    + "lets you remove individual downloads.")
            }
        }
    }
}

struct SettingsPreservationPage: View {
    @State private var showingAvailabilitySweep = false

    var body: some View {
        SettingsPageForm(route: .preservation) {
            Section {
                Button {
                    showingAvailabilitySweep = true
                } label: {
                    Label("Check Availability…", systemImage: "arrow.triangle.2.circlepath")
                }
            } footer: {
                // Deliberately a button, never a background task: it is one AO3
                // request per work and AO3 offers no "what changed" feed, so the
                // user decides when that cost is worth paying.
                Text("Checks which saved works are still on AO3 and marks missing ones as the "
                    + "last copy you have. Kudos checks one work at a time and waits between "
                    + "checks, so start it when you have time.")
            }
        }
        .sheet(isPresented: $showingAvailabilitySweep) {
            AvailabilitySweepView()
        }
    }
}

struct SettingsLibraryPage: View {
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("showsZeroStats") private var showsZeroStats = true

    var body: some View {
        SettingsPageForm(route: .library) {
            Section {
                Toggle("Confirm before deleting", isOn: $confirmBeforeDelete)
                Toggle("Show zero counts", isOn: $showsZeroStats)
            } footer: {
                Text(
                    """
                    Confirm before deleting asks before a swipe removes a work from your Library. \
                    Show zero counts keeps empty stats on work cards; turn it off to hide them.
                    """
                )
            }
        }
    }
}

struct SettingsReadingQueuesPage: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedWork.dateAdded) private var works: [SavedWork]

    @AppStorage("autoPreserveSmallSeriesOnSaveForLater")
    private var autoPreserveSmallSeriesOnSaveForLater = false
    @AppStorage("autoPreserveSeriesWorkThreshold")
    private var autoPreserveSeriesWorkThreshold = 5

    @State private var showSavedWorkMigrationConfirmation = false
    @State private var isMigratingSavedWorks = false
    @State private var savedWorkMigrationProgress: String?
    @State private var savedWorkMigrationCompleted = 0
    @State private var savedWorkMigrationTotal = 0
    @State private var savedWorkMigrationTask: Task<Void, Never>?
    @State private var notice: SettingsNotice?

    private var legacySavedWorksForQueueMigration: [SavedWork] {
        // Recently Deleted works aren't migrated into Saved for Later — queueing one
        // would resurrect a record the user explicitly deleted.
        works.filter { $0.isSaved && !$0.isQueuedForLater && !$0.isPendingDeletion }
    }

    var body: some View {
        SettingsPageForm(route: .readingQueues) {
            Section {
                NavigationLink {
                    ReadingQueueStorageView()
                } label: {
                    Label("Queue Storage", systemImage: "externaldrive")
                }

                Toggle(
                    "Auto-preserve small series",
                    isOn: $autoPreserveSmallSeriesOnSaveForLater
                )
                Stepper(
                    "Series limit: \(autoPreserveSeriesWorkThreshold)",
                    value: $autoPreserveSeriesWorkThreshold,
                    in: 2 ... 25
                )
                .disabled(!autoPreserveSmallSeriesOnSaveForLater)

                if !legacySavedWorksForQueueMigration.isEmpty {
                    Button {
                        showSavedWorkMigrationConfirmation = true
                    } label: {
                        Label("Add Saved Works to Saved for Later", systemImage: "arrow.right.doc.on.clipboard")
                    }
                    .disabled(isMigratingSavedWorks)
                }

                if isMigratingSavedWorks {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(
                            value: Double(savedWorkMigrationCompleted),
                            total: Double(max(savedWorkMigrationTotal, 1))
                        )
                        HStack(spacing: 12) {
                            Text(savedWorkMigrationProgress ?? "Updating Saved for Later…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") {
                                cancelSavedWorkMigration()
                            }
                        }
                    }
                }
            } footer: {
                Text("Saved for Later keeps a downloaded copy. When you save a series, Kudos "
                    + "asks before downloading each work unless this option is on and the series "
                    + "is within your limit.")
            }
        }
        .settingsNoticeAlert($notice)
        .confirmationDialog(
            "Add saved works to Saved for Later?",
            isPresented: $showSavedWorkMigrationConfirmation,
            titleVisibility: .visible
        ) {
            Button(savedWorkMigrationButtonTitle) {
                startSavedWorkMigration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Split out of the ViewBuilder so the type checker can finish
            // (the surrounding modifier chain otherwise times out).
            let migrationMessage =
                "Kudos will add your existing saved works to Saved for Later without changing "
                + "whether they are saved. It makes each one available offline, one at a time, "
                + "with a pause between visits to AO3."
            Text(migrationMessage)
        }
    }

    private var savedWorkMigrationButtonTitle: String {
        let count = legacySavedWorksForQueueMigration.count
        return "Add \(count) Work\(count == 1 ? "" : "s")"
    }

    private func startSavedWorkMigration() {
        guard savedWorkMigrationTask == nil else { return }
        savedWorkMigrationTask = Task(priority: .utility) { @MainActor in
            await migrateLegacySavedWorksToSavedForLater()
            savedWorkMigrationTask = nil
        }
    }

    private func cancelSavedWorkMigration() {
        savedWorkMigrationTask?.cancel()
        savedWorkMigrationProgress = "Cancelling after the current work…"
    }

    @MainActor
    private func migrateLegacySavedWorksToSavedForLater() async {
        let candidates = legacySavedWorksForQueueMigration
        guard !candidates.isEmpty, !isMigratingSavedWorks else { return }

        isMigratingSavedWorks = true
        savedWorkMigrationCompleted = 0
        savedWorkMigrationTotal = candidates.count
        savedWorkMigrationProgress = "Preparing Saved for Later…"
        defer {
            isMigratingSavedWorks = false
            savedWorkMigrationProgress = nil
            savedWorkMigrationCompleted = 0
            savedWorkMigrationTotal = 0
        }

        var added = 0
        var unavailableOffline = 0
        var cancelled = false

        for (index, work) in candidates.enumerated() {
            if Task.isCancelled {
                cancelled = true
                break
            }

            savedWorkMigrationProgress = "Updating \(index + 1) of \(candidates.count)…"
            _ = await ReadingQueueService.addToSavedForLater(work, in: context)
            if work.isInSavedForLaterQueue { added += 1 }
            if !work.hasEPUB || work.epubPreservationStatus == .failed
                || work.epubPreservationStatus == .missingFile {
                unavailableOffline += 1
            }
            savedWorkMigrationCompleted = index + 1

            if Task.isCancelled {
                cancelled = true
                break
            }

            guard index + 1 < candidates.count else { continue }
            savedWorkMigrationProgress = "Waiting before checking the next work on AO3…"
            do {
                try await Task.sleep(nanoseconds: ReadingQueueService.preservationRequestPauseNanos)
            } catch {
                cancelled = true
                break
            }
        }

        var message = "Added \(added.formatted()) saved work"
            + "\(added == 1 ? "" : "s") to Saved for Later."
        if unavailableOffline > 0 {
            message += " \(unavailableOffline.formatted()) need to be downloaded again before offline reading."
        }
        if cancelled {
            message += " The update stopped before the remaining works were changed."
        }

        notice = SettingsNotice(
            title: cancelled ? "Migration Cancelled" : "Saved for Later Updated",
            message: message
        )
    }
}
