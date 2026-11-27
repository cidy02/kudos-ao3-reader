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

    // Board 50's other groups. Each is the same key the page that owns it reads:
    // Preserve series -> Reading Queues, the two Library toggles -> Library,
    // Check Availability -> Preservation. One stored value each, two ways in.
    @AppStorage("autoPreserveSmallSeriesOnSaveForLater") private var autoPreserveSeries = false
    @AppStorage("autoPreserveSeriesWorkThreshold") private var seriesLimit = 5
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("showsZeroStats") private var showsZeroStats = true
    @Query private var works: [SavedWork]
    @State private var showingAvailabilitySweep = false

    private var lastAvailabilityRun: Date? { works.compactMap(\.lastAvailabilityCheck).max() }

    /// Board `Settings-Storage`: "Up to N works" when auto-preserve is on, "Ask first" when off.
    static func preserveSeriesValue(autoPreserve: Bool, seriesLimit: Int) -> String {
        autoPreserve ? "Up to \(seriesLimit) works" : "Ask first"
    }

    /// Board `Settings-Storage`: "Last run Oct 20".
    static func lastRunValue(for date: Date) -> String {
        "Last run \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        SettingsPageForm(route: .downloads) {
            Section {
                StorageSummaryRow()
            }
            Section {
                Toggle("Download on subscribe", isOn: $downloadOnSubscribe).accentFill()
                Toggle("Keep works you read", isOn: $keepsWorksYouRead).accentFill()
                NavigationLink(value: SettingsRoute.readingQueues) {
                    LabeledContent(
                        "Preserve series",
                        value: Self.preserveSeriesValue(autoPreserve: autoPreserveSeries, seriesLimit: seriesLimit)
                    )
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("When you subscribe to a work already in your Library, Kudos downloads it "
                    + "if no copy is stored. Keep works you read keeps every work you open "
                    + "downloaded; when it's off, finishing a work removes its copy unless you "
                    + "downloaded, favorited, or queued it.")
            }
            Section {
                Toggle("Show zero counts", isOn: $showsZeroStats).accentFill()
                Toggle("Confirm before deleting", isOn: $confirmBeforeDelete).accentFill()
            } header: {
                Text("Library")
            }
            Section {
                Button {
                    showingAvailabilitySweep = true
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            if let date = lastAvailabilityRun {
                                Text(Self.lastRunValue(for: date))
                                    .foregroundStyle(.secondaryInk)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    } label: {
                        Text("Check Availability")
                            .foregroundStyle(.accentInk)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Check Availability")
                .accessibilityValue(lastAvailabilityRun.map { Self.lastRunValue(for: $0) } ?? "")
            } header: {
                Text("AO3")
            }
        }
        .sheet(isPresented: $showingAvailabilitySweep) {
            AvailabilitySweepView()
        }
    }
}

struct SettingsPreservationPage: View {
    @Query private var works: [SavedWork]
    @State private var showingAvailabilitySweep = false

    static let sectionHeader = "Works that leave AO3"
    static let checkAvailabilityTitle = "Check what’s still on AO3"
    static let footerText = "Kudos never deletes a work because AO3 lost it."

    /// Board `Settings-Preservation`: "Last: Oct 20".
    static func lastCheckedLabel(for date: Date) -> String {
        "Last: \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var lastAvailabilityRun: Date? { works.compactMap(\.lastAvailabilityCheck).max() }

    var body: some View {
        SettingsPageForm(route: .preservation) {
            Section {
                Button {
                    showingAvailabilitySweep = true
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            if let date = lastAvailabilityRun {
                                Text(Self.lastCheckedLabel(for: date))
                                    .foregroundStyle(.secondaryInk)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIconTile(color: Color(hex: "#1E63C8") ?? .blue, systemImage: "globe")
                            Text(Self.checkAvailabilityTitle)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Self.checkAvailabilityTitle)
                .accessibilityValue(lastAvailabilityRun.map { Self.lastCheckedLabel(for: $0) } ?? "")
            } header: {
                Text(Self.sectionHeader)
            } footer: {
                // Deliberately a button, never a background task: it is one AO3
                // request per work and AO3 offers no "what changed" feed, so the
                // user decides when that cost is worth paying (`AvailabilitySweepView`
                // explains the wait before starting).
                Text(Self.footerText)
            }
        }
        .sheet(isPresented: $showingAvailabilitySweep) {
            AvailabilitySweepView()
        }
        #if DEBUG
        .task { if DebugLaunchRoute.takeSheet("availability") { showingAvailabilitySweep = true } }
        #endif
    }
}

struct SettingsLibraryPage: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(PrivacyGate.self) private var gate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var works: [SavedWork]
    @Query(filter: #Predicate<WorkCollection> { !$0.isPendingDeletion }) private var collections: [WorkCollection]
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }) private var readingQueues: [ReadingQueue]

    @AppStorage(LibraryPageArrangement.storageKey) private var pageArrangement = LibraryPageArrangement.default
    @AppStorage(WorkSymbolPlacement.storageKey) private var symbolPlacement: WorkSymbolPlacement = .defaultValue
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("showsZeroStats") private var showsZeroStats = true
    @AppStorage(SavedSeriesWeeklyCheck.enabledKey) private var checksSavedSeriesWeekly = true

    @State private var showingEditShelves = false

    static let workListsFooter = "Row puts the four symbols under the title. Grid keeps them in a square beside it."

    /// Board `Settings-Library`: "6 shown".
    static func shelvesShownLabel(count: Int) -> String {
        "\(count) shown"
    }

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var allWorksCount: Int {
        works.filter { !$0.isQueueOnlyWork && passesPrivacy($0) }.count
    }

    private var shelfCounts: [LibraryShelfID: Int] {
        Dictionary(uniqueKeysWithValues: LibraryShelfID.allCases.map { ($0, shelfCount($0)) })
    }

    private func shelfCount(_ shelf: LibraryShelfID) -> Int {
        switch shelf {
        case .favourites: LibrarySectionKind.favorites.works(from: works, visible: passesPrivacy).count
        case .collections: collections.count
        case .downloaded: LibrarySectionKind.downloaded.works(from: works, visible: passesPrivacy).count
        case .wantToRead: LibrarySectionKind.savedForLater.works(from: works, visible: passesPrivacy).count
        case .readingNow: LibrarySectionKind.readingNow.works(from: works, visible: passesPrivacy).count
        case .finished: LibrarySectionKind.finished.works(from: works, visible: passesPrivacy).count
        case .queues: readingQueues.filter(\.isUserQueue).count
        case .history: LibrarySectionKind.history.works(from: works, visible: passesPrivacy).count
        case .imported:
            works.filter {
                LibraryShelfID.isImported(origin: $0.origin, isQueueOnly: $0.isQueueOnlyWork) && passesPrivacy($0)
            }.count
        }
    }

    private var symbolsPicker: some View {
        Picker("Symbols", selection: $symbolPlacement) {
            Text("Row").tag(WorkSymbolPlacement.underTitle)
            Text("Grid").tag(WorkSymbolPlacement.beside)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accentFill()
        .accessibilityLabel("Symbols")
    }

    private var shelvesSection: some View {
        Section {
            Button {
                showingEditShelves = true
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(Self.shelvesShownLabel(count: pageArrangement.sections.count))
                            .foregroundStyle(.secondaryInk)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#C25E00") ?? .orange, systemImage: "books.vertical")
                        Text("Edit Shelves")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Edit Shelves")
            .accessibilityValue(Self.shelvesShownLabel(count: pageArrangement.sections.count))
        } header: {
            Text("Shelves")
        }
    }

    var body: some View {
        SettingsPageForm(route: .library) {
            shelvesSection

            Section {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Symbols")
                            .fixedSize(horizontal: false, vertical: true)
                        symbolsPicker
                    }
                } else {
                    LabeledContent("Symbols") {
                        symbolsPicker
                            .fixedSize()
                    }
                }
            } header: {
                Text("Work lists")
            } footer: {
                Text(Self.workListsFooter)
            }
            .onChange(of: symbolPlacement) { _, _ in
                NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
            }

            Section {
                LabeledContent {
                    Text(PreservedWorkService.recoveryWindowText)
                        .foregroundStyle(.secondaryInk)
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#8E8E93") ?? .gray, systemImage: "trash")
                        Text("Keep deleted works for")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Keep deleted works for")
                .accessibilityValue(PreservedWorkService.recoveryWindowText)
            } header: {
                Text("Recently Deleted")
            }

            Section {
                Toggle("Confirm before deleting", isOn: $confirmBeforeDelete).accentFill()
                Toggle("Show zero counts", isOn: $showsZeroStats).accentFill()
            } footer: {
                Text(
                    """
                    Confirm before deleting asks before a swipe removes a work from your Library. \
                    Show zero counts keeps empty stats on work cards; turn it off to hide them.
                    """
                )
            }
            Section {
                Toggle("Check saved series weekly", isOn: $checksSavedSeriesWeekly).accentFill()
            } footer: {
                Text(
                    """
                    Once a week, Kudos asks AO3 whether a series you have opened has new parts, a few at a time and \
                    spread across the week. Series whose AO3 notifications reach Kudos are never asked. Turn it off \
                    and a series updates only when you open it.
                    """
                )
            }
        }
        .sheet(isPresented: $showingEditShelves) {
            LibraryEditShelvesSheet(
                arrangement: $pageArrangement,
                counts: shelfCounts,
                allWorksCount: allWorksCount
            )
            .environment(themeManager)
            .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
        }
        .onChange(of: pageArrangement) { _, _ in
            NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
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
    #if DEBUG
    @State private var debugStorage = false
    #endif

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
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#007AFF") ?? .blue, systemImage: "externaldrive")
                        Text("Queue Storage")
                    }
                }

                Toggle(
                    "Auto-preserve small series",
                    isOn: $autoPreserveSmallSeriesOnSaveForLater
                )
                .accentFill()
                Stepper(
                    "Series limit: \(autoPreserveSeriesWorkThreshold)",
                    value: $autoPreserveSeriesWorkThreshold,
                    in: 2 ... 25
                )
                .disabled(!autoPreserveSmallSeriesOnSaveForLater).accentFill()

                if !legacySavedWorksForQueueMigration.isEmpty {
                    Button {
                        showSavedWorkMigrationConfirmation = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIconTile(color: Color(hex: "#FF9500") ?? .orange, systemImage: "arrow.right.doc.on.clipboard")
                            Text("Add Saved Works to Want to Read")
                        }
                    }
                    .disabled(isMigratingSavedWorks)
                }

                if isMigratingSavedWorks {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(
                            value: Double(savedWorkMigrationCompleted),
                            total: Double(max(savedWorkMigrationTotal, 1))
                        )
                        .accentFill()
                        HStack(spacing: 12) {
                            Text(savedWorkMigrationProgress ?? "Updating Want to Read…")
                                .font(.footnote)
                                .foregroundStyle(.secondaryInk)
                            Spacer()
                            Button("Cancel") {
                                cancelSavedWorkMigration()
                            }
                        }
                    }
                }
            } footer: {
                Text("Want to Read keeps a downloaded copy. When you save a series, Kudos "
                    + "asks before downloading each work unless this option is on and the series "
                    + "is within your limit.")
            }
        }
        .settingsNoticeAlert($notice)
        .confirmationDialog(
            "Add saved works to Want to Read?",
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
                "Kudos will add your existing saved works to Want to Read without changing "
                + "whether they are saved. It makes each one available offline, one at a time, "
                + "with a pause between visits to AO3."
            Text(migrationMessage)
        }
        #if DEBUG
        .task {
            guard DebugLaunchRoute.takePush("queuestorage") else { return }
            try? await Task.sleep(for: .seconds(1))
            debugStorage = true
        }
        // A sheet: a push made from this page, itself pushed by the launch route, never happened.
        .sheet(isPresented: $debugStorage) { NavigationStack { ReadingQueueStorageView() } }
        #endif
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
        savedWorkMigrationProgress = "Preparing Want to Read…"
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
            _ = await ReadingQueueService.addToSavedForLater(
                work,
                state: .new,
                origin: ReadingQueueMembershipOrigin(kind: .manual),
                in: context
            )
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
            + "\(added == 1 ? "" : "s") to Want to Read."
        if unavailableOffline > 0 {
            message += " \(unavailableOffline.formatted()) need to be downloaded again before offline reading."
        }
        if cancelled {
            message += " The update stopped before the remaining works were changed."
        }

        notice = SettingsNotice(
            title: cancelled ? "Migration Cancelled" : "Want to Read Updated",
            message: message
        )
    }
}
