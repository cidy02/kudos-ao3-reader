import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// A status decision from Library's untouched-work prompt. Edits stay on a draft
/// until saved through `WorkLifecycle`; this sheet never visits AO3.
struct InsightsStoppedSheet: View {
    struct Draft: Equatable {
        var reason: String
        var tag: String
        var note: String

        init(work: SavedWork) {
            reason = work.stopReasonRaw.isEmpty ? "lostInterest" : work.stopReasonRaw
            tag = work.stopTag
            note = work.stopNote
        }
    }

    let work: SavedWork
    let discreetMode: Bool
    let discreetMasker: InsightsDiscreetMasker
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @State private var draft: Draft
    @State private var saveError: String?

    init(
        work: SavedWork,
        discreetMode: Bool,
        discreetMasker: InsightsDiscreetMasker,
        onChanged: @escaping () -> Void
    ) {
        self.work = work
        self.discreetMode = discreetMode
        self.discreetMasker = discreetMasker
        self.onChanged = onChanged
        _draft = State(initialValue: Draft(work: work))
    }

    private struct ReasonChoice: Identifiable {
        let id: String
        let label: String
    }
    private let reasons: [ReasonChoice] = [
        .init(id: "lostInterest", label: "Lost Interest"),
        .init(id: "tooLong", label: "Too Long"),
        .init(id: "writingStyle", label: "Writing Style"),
        .init(id: "tagDealbreaker", label: "Tag Dealbreaker"),
        .init(id: "gotSpoiled", label: "Got Spoiled"),
        .init(id: "other", label: "Other")
    ]

    private var availableTags: [String] {
        let freeforms = ReadingInsights.freeformTags(of: work)
        let cleaned = (work.workWarnings + freeforms)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted()
    }

    /// Builds the board's chapter / progress / last-read context line (e.g.
    /// "Chapter 7 of 12 · 58% · last read Oct 6"), omitting unrecorded parts.
    static func progressSummary(for work: SavedWork) -> String {
        var parts: [String] = []
        if let locatorTitle = WorkReadingPosition.title(from: work.readiumLocator) {
            parts.append(locatorTitle)
        } else if work.postedChapterCount > 0 {
            let current = min(work.postedChapterCount, max(1, work.lastSpineIndex + 1))
            parts.append("Chapter \(current) of \(work.postedChapterCount)")
        }
        if let progress = work.readingProgress {
            parts.append("\(Int((progress * 100).rounded()))%")
        }
        if let lastRead = work.lastReadDate {
            parts.append("last read \(lastRead.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let rawFandom = work.workFandoms.first, !rawFandom.isEmpty {
                        Text(discreetMode ? discreetMasker.fandom(rawFandom) : rawFandom)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    Text(discreetMode ? discreetMasker.work(id: work.id, title: work.title) : work.title)
                        .font(.headline)
                    let progressLine = Self.progressSummary(for: work)
                    if !progressLine.isEmpty {
                        Text(progressLine)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                    }
                }
                .appThemedRows()

                Section("Reason") {
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(reasons) { choice in
                            Button(choice.label) { draft.reason = choice.id }
                                .buttonStyle(.bordered)
                                .tint(draft.reason == choice.id ? theme.effectiveTint : .secondary)
                                .accessibilityAddTraits(draft.reason == choice.id ? .isSelected : [])
                        }
                    }
                }
                .appThemedRows()

                if !availableTags.isEmpty {
                    Section("Which Tag") {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(availableTags, id: \.self) { choice in
                                Button(discreetMode ? discreetMasker.tag(choice) : choice) {
                                    draft.tag = draft.tag == choice ? "" : choice
                                }
                                .buttonStyle(.bordered)
                                .tint(draft.tag == choice ? theme.effectiveTint : .secondary)
                                .accessibilityAddTraits(draft.tag == choice ? .isSelected : [])
                            }
                        }
                    }
                    .appThemedRows()
                }

                Section("Private Note") {
                    TextField("Optional note", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                }
                .appThemedRows()

                Section {
                    Button("Mark as Stopped") {
                        saveStatus {
                            try WorkLifecycle.recordStopped(
                                work,
                                reason: draft.reason,
                                tag: draft.tag,
                                note: draft.note,
                                in: context
                            )
                        }
                    }
                    .fontWeight(.semibold)
                    Button("Put On Hold Instead") {
                        saveStatus {
                            try WorkLifecycle.setReadingStatus(.onHold, for: work, in: context)
                        }
                    }
                }
                .appThemedRows()
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .appThemedScroll()
            .navigationTitle("Stopped Reading?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .wrappingInlineTitle("Stopped Reading?", isActive: dynamicTypeSize.isAccessibilitySize)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            } }
        }
        #if os(iOS)
        .modifier(ScopeSurfaceAccent())
        #endif
        .alert("Couldn’t Save Reading Status", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func saveStatus(_ commit: () throws -> Void) {
        do {
            try commit()
            onChanged()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Artboard **07** / `Insights-Options.dc.html` — Insights Options sheet.
///
/// Controls privacy, counting rules, exclusions, export (CSV / JSON), and log reset.
struct InsightsOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme

    @AppStorage(InsightsOptions.Keys.discreetMode) private var discreetMode: Bool = false
    @AppStorage(InsightsOptions.Keys.hideReadingTime) private var hideReadingTime: Bool = false
    @AppStorage(InsightsOptions.Keys.countRereads) private var countRereads: Bool = true
    @AppStorage(InsightsOptions.Keys.countReadAloud) private var countReadAloud: Bool = true
    @AppStorage(InsightsOptions.Keys.askAboutUntouched) private var askAboutUntouched: Bool = true
    @AppStorage(InsightsOptions.Keys.untouchedDays)
    private var untouchedDays: Int = InsightsOptions.defaultUntouchedDays

    /// The main scope used by Exclusions: choices never name live, soft-deleted, or
    /// hard-deleted hidden mature works.
    let exclusionsScope: InsightsScopeSelection
    /// What the screen counts (main, or combined while revealed); the export follows it.
    let exportScope: InsightsScopeSelection
    @Binding var includeHidden: Bool
    /// Hide Mature is on and the privacy gate is revealed.
    var canIncludeHidden = false
    let onShowHowCounted: () -> Void
    let onOptionsChanged: () -> Void

    private var isPrivacyLocked: Bool {
        exportScope.hideMature && !exportScope.revealed
    }

    private var resetAlertCopy: InsightsResetAlertCopy {
        InsightsResetAlertCopy.make(counts: resetCounts, isPrivacyLocked: isPrivacyLocked)
    }

    @State private var excludedFandoms: [String] = []
    @State private var excludedTags: [String] = []
    @State private var excludedWorkIDs: [String] = []

    @State private var showingExportFormatDialog = false
    @State private var exportedShareItem: InsightsShareItem?
    @State private var exportFailure: String?
    #if os(macOS)
    @State private var macExportDocument: InsightsExportFileDocument?
    @State private var macExportFormat: InsightsExportFormat = .csv
    @State private var showingMacExporter = false
    #endif

    @State private var resetCounts = InsightsResetCounts(sessionCount: 0, workCount: 0)
    @State private var showingResetAlert = false
    @State private var resetFailure: String?

    private static let untouchedDayPresets = [7, 14, 21, 28, 42, 56]

    private var excludedCount: Int {
        excludedFandoms.count + excludedTags.count + excludedWorkIDs.count
    }

    private var untouchedDurationText: String {
        let days = InsightsOptions.clampUntouchedDays(untouchedDays)
        if days % 7 == 0 {
            let weeks = max(1, days / 7)
            return "\(weeks) \(weeks == 1 ? "week" : "weeks")"
        }
        return "\(days) \(days == 1 ? "day" : "days")"
    }

    private var untouchedDayChoices: [Int] {
        var choices = Self.untouchedDayPresets
        let clamped = InsightsOptions.clampUntouchedDays(untouchedDays)
        if !choices.contains(clamped) {
            choices.append(clamped)
            choices.sort()
        }
        return choices
    }

    var body: some View {
        NavigationStack {
            List {
                privacySection
                if canIncludeHidden {
                    hiddenSection
                }
                whatCountsSection
                readingHistorySection
                howCountedSection
            }
            .appThemedScroll()
            .navigationTitle("Insights Options")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .wrappingInlineTitle("Insights Options", isActive: dynamicTypeSize.isAccessibilitySize)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(theme.accentInk)
                }
            }
            .onAppear {
                reloadStoredExclusions()
            }
            .onChange(of: discreetMode) { _, _ in notifyOptionChange() }
            .onChange(of: hideReadingTime) { _, _ in notifyOptionChange() }
            .onChange(of: countRereads) { _, _ in notifyOptionChange() }
            .onChange(of: countReadAloud) { _, _ in notifyOptionChange() }
            .onChange(of: askAboutUntouched) { _, _ in notifyOptionChange() }
            .onChange(of: untouchedDays) { _, _ in notifyOptionChange() }
            .confirmationDialog(
                "Export Reading History",
                isPresented: $showingExportFormatDialog,
                titleVisibility: .visible
            ) {
                Button("Export as CSV") {
                    exportHistory(format: .csv)
                }
                Button("Export as JSON") {
                    exportHistory(format: .json)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "CSV saves one row per sitting and work status. "
                        + "JSON saves sittings, statuses, reasons and notes."
                )
            }
            .alert(
                resetAlertCopy.title,
                isPresented: $showingResetAlert
            ) {
                if let destructiveTitle = resetAlertCopy.destructiveButtonTitle {
                    Button("Cancel", role: .cancel) {}
                    Button(destructiveTitle, role: .destructive) {
                        resetReadingLog()
                    }
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(resetAlertCopy.message)
            }
            .alert("Couldn’t Export Reading History", isPresented: Binding(
                get: { exportFailure != nil },
                set: { if !$0 { exportFailure = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportFailure ?? "")
            }
            .alert("Couldn’t Reset Insights", isPresented: Binding(
                get: { resetFailure != nil },
                set: { if !$0 { resetFailure = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resetFailure ?? "")
            }
            #if os(iOS)
            .sheet(item: $exportedShareItem) { item in
                InsightsExportActivitySheet(url: item.url) {
                    InsightsShareItem.cleanUp(item.url)
                    exportedShareItem = nil
                }
            }
            #else
            .fileExporter(
                isPresented: $showingMacExporter,
                document: macExportDocument,
                contentType: macExportFormat.contentType,
                defaultFilename: "Kudos-Reading-History.\(macExportFormat.fileExtension)"
            ) { result in
                if case .failure(let error) = result {
                    exportFailure = error.localizedDescription
                }
                macExportDocument = nil
            }
            #endif
        }
        #if os(iOS)
        .modifier(ScopeSurfaceAccent())
        #endif
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: $discreetMode) {
                Label {
                    Text("Discreet Mode")
                } icon: {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accentFill()

            Toggle(isOn: $hideReadingTime) {
                Label {
                    Text("Hide Reading Time")
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accentFill()
        } header: {
            Text("Privacy")
        } footer: {
            Text("Discreet Mode hides fandom, relationship, character and tag names here and in exports. Totals stay.")
        }
        .appThemedRows()
    }

    /// Session-only: the screen turns it off when the gate re-locks, and it is never stored.
    private var hiddenSection: some View {
        Section {
            Toggle(isOn: $includeHidden) {
                Label {
                    Text("Include Hidden")
                } icon: {
                    Image(systemName: "eye")
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accentFill()
            .accessibilityHint("Counts hidden mature works in every figure and export until Mature is hidden again")
        } header: {
            Text("Hidden")
        } footer: {
            Text("Counts hidden mature works in every figure and export. Turns off when Mature is hidden again.")
        }
        .appThemedRows()
    }

    private var whatCountsSection: some View {
        Section {
            Toggle(isOn: $countRereads) {
                Label {
                    Text("Count Rereads in Totals")
                } icon: {
                    Image(systemName: "arrow.2.circlepath")
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accentFill()

            Toggle(isOn: $countReadAloud) {
                Label {
                    Text("Count Read Aloud as Reading")
                } icon: {
                    Image(systemName: "headphones")
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accentFill()

            Toggle(isOn: $askAboutUntouched) {
                Label {
                    Text("Ask About Untouched Works")
                } icon: {
                    Image(systemName: "questionmark.bubble")
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accentFill()

            if askAboutUntouched {
                Picker(selection: $untouchedDays) {
                    ForEach(untouchedDayChoices, id: \.self) { days in
                        Text(labelForDays(days)).tag(days)
                    }
                } label: {
                    Label {
                        Text("Ask After")
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.secondaryInk)
                    }
                }
                .accessibilityLabel("Ask after untouched period")
            }

            NavigationLink {
                InsightsExclusionsView(
                    scope: exclusionsScope,
                    excludedFandoms: $excludedFandoms,
                    excludedTags: $excludedTags,
                    excludedWorkIDs: $excludedWorkIDs,
                    onChange: persistExclusions
                )
            } label: {
                HStack(spacing: 8) {
                    Label {
                        Text("Left Out of Insights")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondaryInk)
                    }
                    Spacer()
                    Text("\(excludedCount)")
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Left Out of Insights")
            .accessibilityValue("\(excludedCount) excluded")
        } header: {
            Text("What Counts")
        } footer: {
            Text(
                "Kudos asks after \(untouchedDurationText) without opening a work "
                    + "you’re partway through. A work is only marked stopped when you say so."
            )
        }
        .appThemedRows()
    }

    private var readingHistorySection: some View {
        Section {
            Button {
                showingExportFormatDialog = true
            } label: {
                Label {
                    Text("Export Reading History…")
                        .foregroundStyle(theme.accentInk)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(theme.accentInk)
                }
            }
            .accessibilityHint("Choose CSV or JSON format to share")

            Button(role: .destructive) {
                resetCounts = InsightsExportService.resetCounts(
                    in: modelContext,
                    scope: isPrivacyLocked ? exportScope : nil
                )
                showingResetAlert = true
            } label: {
                Label {
                    Text("Reset Insights…")
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
            .accessibilityHint("Deletes your local reading log while keeping works, progress and statuses")
        } header: {
            Text("Reading History")
        } footer: {
            Text(
                "Export saves sessions, statuses and reasons as CSV or JSON. "
                    + "Reset deletes the reading log only; works, progress and statuses stay."
            )
        }
        .appThemedRows()
    }

    private var howCountedSection: some View {
        Section {
            Button {
                onShowHowCounted()
            } label: {
                HStack {
                    Label {
                        Text("How Reading Insights Are Counted")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        }
        .appThemedRows()
    }

    private func labelForDays(_ days: Int) -> String {
        if days % 7 == 0 {
            let weeks = max(1, days / 7)
            return "\(weeks) \(weeks == 1 ? "week" : "weeks")"
        }
        return "\(days) \(days == 1 ? "day" : "days")"
    }

    private func reloadStoredExclusions() {
        let current = InsightsOptions.load()
        excludedFandoms = current.excludedFandoms
        excludedTags = current.excludedTags
        excludedWorkIDs = current.excludedWorkIDs
    }

    private func persistExclusions(_ kind: InsightsOptions.ExclusionKind) {
        switch kind {
        case .fandoms:
            excludedFandoms = InsightsOptions.saveExcludedFandoms(excludedFandoms, notifySync: true)
        case .tags:
            excludedTags = InsightsOptions.saveExcludedTags(excludedTags, notifySync: true)
        case .workIDs:
            excludedWorkIDs = InsightsOptions.saveExcludedWorkIDs(excludedWorkIDs, notifySync: true)
        case .all:
            InsightsOptions.clearAllExclusions(notifySync: true)
        }
        onOptionsChanged()
    }

    private func notifyOptionChange() {
        NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
        onOptionsChanged()
    }

    private func exportHistory(format: InsightsExportFormat) {
        let works = exportScope.libraryWorks
        let readingWorks = exportScope.readingWorks
        let sessions = exportScope.sessions(
            (try? modelContext.fetch(FetchDescriptor<ReadingSession>())) ?? [],
            in: modelContext
        )
        let options = InsightsOptions.load()
        let aliases = TagAliasStore.resolver(in: modelContext)
        do {
            #if os(iOS)
            let url = try InsightsExportService.writeTemporaryExportFile(
                format: format,
                works: works,
                readingWorks: readingWorks,
                sessions: sessions,
                options: options,
                aliases: aliases
            )
            exportedShareItem = InsightsShareItem(url: url)
            #else
            let data: Data
            switch format {
            case .csv:
                data = Data(InsightsExportService.csvString(
                    works: works,
                    readingWorks: readingWorks,
                    sessions: sessions,
                    options: options,
                    aliases: aliases
                ).utf8)
            case .json:
                data = try InsightsExportService.jsonData(
                    works: works,
                    readingWorks: readingWorks,
                    sessions: sessions,
                    options: options,
                    aliases: aliases
                )
            }
            macExportFormat = format
            macExportDocument = InsightsExportFileDocument(data: data, contentType: format.contentType)
            showingMacExporter = true
            #endif
        } catch {
            exportFailure = error.localizedDescription
        }
    }

    private func resetReadingLog() {
        do {
            try InsightsExportService.resetReadingLog(in: modelContext)
            onOptionsChanged()
        } catch {
            modelContext.rollback()
            resetFailure = error.localizedDescription
        }
    }
}

/// Artboard **07** / `Insights-Metrics.dc.html` — How Reading Insights Are Counted.
///
/// Plain-English explanation of metric rules, calculations, and local privacy.
struct HowInsightsAreCountedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metricSection(
                        title: "Device-Only Privacy",
                        symbol: "lock.shield",
                        paragraphs: [
                            "Reading Insights are computed entirely on your device from your local reading log.",
                            "Nothing about what you read, when you read, or how fast you read is ever uploaded or sent anywhere."
                        ]
                    )

                    metricSection(
                        title: "Overview",
                        symbol: "chart.bar.xaxis",
                        paragraphs: [
                            "Words read: The sum of words read across your sittings in the period, based on your movement through each work and its AO3 word count.",
                            "Novels’ worth: Words read divided by 70,000, rounded to the nearest half novel. Shown when you have read at least 35,000 words.",
                            "Pace: Weighted words per hour across your active reading sessions. Sittings under 15 seconds are excluded so brief opens do not dilute your speed.",
                            "Longest streak: The longest run of consecutive calendar days with at least one recorded reading session."
                        ]
                    )

                    metricSection(
                        title: "Taste",
                        symbol: "sparkles",
                        paragraphs: [
                            "Your Usual Fic: Derived from your most frequent fandom, rating, category, and length among works read.",
                            "Fandoms & Ships: Attributed to each work's primary fandom and tagged relationships. Romantic (/) and platonic (&) bonds are distinguished.",
                            "Ship concentration: The share of a fandom’s words centered on its top relationship tag."
                        ]
                    )

                    metricSection(
                        title: "Habits",
                        symbol: "clock.arrow.circlepath",
                        paragraphs: [
                            "Time of Day: Tracks the local hours when your reading takes place, highlighting late-night reading between 1:00 AM and 5:00 AM.",
                            "Reading Days: A calendar heat map indicating days with reading activity in four color tiers based on words read.",
                            "Sittings: The median duration of your reading stretches, ignoring background pauses."
                        ]
                    )

                    metricSection(
                        title: "Library",
                        symbol: "books.vertical",
                        paragraphs: [
                            "Statuses: Every work in your library is partitioned into exactly one status: Reading, Caught Up, Letting Chapters Stack, On Hold, Saved for Later, Finished, or Stopped.",
                            "Works in Progress: Categorized as Active (updated in the last 6 months), Quiet (6 to 12 months), or Dormant (over a year).",
                            "No Longer on AO3: Identifies works you downloaded whose original AO3 pages are no longer available, safely preserved on your device."
                        ]
                    )
                }
                .padding(16)
            }
            .background(theme.appTheme.cardBackdrop)
            .navigationTitle("How Insights Are Counted")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(theme.effectiveTint)
                }
            }
        }
    }

    private func metricSection(title: String, symbol: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.effectiveTint)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}
