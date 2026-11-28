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
    /// In Discreet Mode, free-text Readium chapter titles are replaced by numeric
    /// chapter counts so custom AO3 titles cannot leak ship or character names.
    static func progressSummary(for work: SavedWork, discreetMode: Bool = false) -> String {
        var parts: [String] = []
        if !discreetMode, let locatorTitle = WorkReadingPosition.title(from: work.readiumLocator) {
            parts.append(locatorTitle)
        } else if work.postedChapterCount > 0 {
            let current = min(work.postedChapterCount, max(1, work.lastSpineIndex + 1))
            // Same wording as the reader: the work's total when known, else the bare chapter number.
            parts.append(SavedWork.totalChapterCount(from: work.chapters).map { (total: Int) -> String in "Chapter \(current) of \(total)" } ?? "Chapter \(current)")
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
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    workSummaryCard

                    sectionHeading("Reason")
                        .padding(.top, 10)

                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(reasons) { choice in
                            let isSelected = draft.reason == choice.id
                            Button {
                                draft.reason = choice.id
                            } label: {
                                Text(choice.label)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(
                                        isSelected
                                            ? ThemeManager.label(on: theme.effectiveTint)
                                            : Color.primary
                                    )
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: 34)
                                    .background(isSelected ? theme.effectiveTint : theme.appTheme.cardSurface)
                                    .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                                    .overlay(
                                        SubjectMetrics.controlShape(dynamicTypeSize)
                                            .strokeBorder(
                                                isSelected ? Color.clear : theme.appTheme.cardBorder,
                                                lineWidth: 0.5
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.label)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 2)

                    sectionHeading(availableTags.isEmpty ? "Private Note" : "Which Tag")
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 0) {
                        if !availableTags.isEmpty {
                            FlowLayout(spacing: 8, rowSpacing: 8) {
                                ForEach(availableTags, id: \.self) { choice in
                                    let isSelected = draft.tag == choice
                                    let label = discreetMode ? discreetMasker.tag(choice) : choice
                                    Button {
                                        draft.tag = isSelected ? "" : choice
                                    } label: {
                                        Text(label)
                                            .font(.subheadline)
                                            .foregroundStyle(isSelected ? theme.accentInk : Color.primary)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 5)
                                            .frame(minHeight: 30)
                                            .background(
                                                isSelected
                                                    ? theme.accentInk.opacity(theme.appTheme.isDarkFamily ? 0.22 : 0.12)
                                                    : Color.primary.opacity(0.06)
                                            )
                                            .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                                            .overlay(
                                                SubjectMetrics.controlShape(dynamicTypeSize)
                                                    .strokeBorder(
                                                        isSelected ? theme.accentInk : Color.clear,
                                                        lineWidth: 1.5
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(label)
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .padding(.horizontal, SubjectMetrics.gutter)

                            Divider()
                                .overlay(theme.appTheme.cardBorder)
                        }

                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "pencil")
                                .font(.system(size: 17))
                                .foregroundStyle(.secondaryInk)
                                .frame(width: 22)
                                .accessibilityHidden(true)

                            TextField("Private Note", text: $draft.note, axis: .vertical)
                                .font(.callout)
                                .lineLimit(1...5)
                                .accessibilityLabel("Private Note")
                        }
                        .padding(.horizontal, SubjectMetrics.gutter)
                        .padding(.vertical, 11)
                        .frame(minHeight: 46)
                    }
                    .background(theme.appTheme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                    )

                    VStack(spacing: 8) {
                        Button {
                            saveStatus {
                                try WorkLifecycle.recordStopped(
                                    work,
                                    reason: draft.reason,
                                    tag: draft.tag,
                                    note: draft.note,
                                    in: context
                                )
                            }
                        } label: {
                            Text("Mark as Stopped")
                                .font(.headline)
                                .foregroundStyle(ThemeManager.label(on: theme.effectiveTint))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 50)
                                .padding(.horizontal, 16)
                                .background(theme.effectiveTint)
                                .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                        }
                        .buttonStyle(.plain)

                        Button {
                            saveStatus {
                                try WorkLifecycle.setReadingStatus(.onHold, for: work, in: context)
                            }
                        } label: {
                            Text("Put On Hold Instead")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 50)
                                .padding(.horizontal, 16)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .appThemedScroll()
            .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
            .navigationTitle("Stopped Reading?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .wrappingInlineTitle("Stopped Reading?", isActive: dynamicTypeSize.isAccessibilitySize)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(
                        title: "Close",
                        systemImage: "xmark",
                        tint: .primary
                    ) {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        #if os(iOS)
        .modifier(ScopeSurfaceAccent())
        .presentationDragIndicator(.visible)
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

    private var workSummaryCard: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let rawFandom = work.workFandoms.first, !rawFandom.isEmpty {
                let hue = CoverArt.workHue(fandoms: [rawFandom], title: "")
                HStack(spacing: 6) {
                    Circle()
                        .fill(theme.appTheme.subjectPalette(hue: hue).accent)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(discreetMode ? discreetMasker.fandom(rawFandom) : rawFandom)
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
            }
            Text(discreetMode ? discreetMasker.work(id: work.id, title: work.title) : work.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            let progressLine = Self.progressSummary(for: work, discreetMode: discreetMode)
            if !progressLine.isEmpty {
                Text(progressLine)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .padding(.horizontal, SubjectMetrics.gutter)
            .accessibilityAddTraits(.isHeader)
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
                    ToolbarIconButton(
                        title: "Close",
                        systemImage: "xmark",
                        tint: .primary
                    ) {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
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
        .presentationDragIndicator(.visible)
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
                .textCase(nil)
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
                .textCase(nil)
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
                .textCase(nil)
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
                .textCase(nil)
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
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How Reading Insights Are Counted")
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
    nonisolated struct MetricRuleSection: Equatable, Sendable, Identifiable {
        var id: String { title }
        let title: String
        let symbol: String
        let paragraphs: [String]
    }

    nonisolated static let sheetTitle = "How Reading Insights Are Counted"

    nonisolated static let sections: [MetricRuleSection] = [
        MetricRuleSection(
            title: "Device-Only Privacy",
            symbol: "lock.shield",
            paragraphs: [
                "Reading Insights are computed entirely on your device from your local reading log.",
                "Nothing about what you read, when you read, or how fast you read is ever uploaded or sent anywhere."
            ]
        ),
        MetricRuleSection(
            title: "Shared Rules",
            symbol: "checklist",
            paragraphs: [
                "A period is the dates on screen. Sittings under 15 seconds never count, and visits under 5 minutes apart are joined as one sitting for typical sitting length.",
                "A reading day runs 4:00 to 4:00 in the time zone the sitting was read in, so a late night past midnight stays one day and one streak.",
                "A period is compared with the same number of days of the one before. Rereads count unless the option is off, Read Aloud counts as time and never as pace, and excluded fandoms, tags and works are left out of everything."
            ]
        ),
        MetricRuleSection(
            title: "Overview",
            symbol: "chart.bar.xaxis",
            paragraphs: [
                "Words read: Each sitting’s advance through a work in words (never below zero), using per-chapter EPUB word counts when available and falling back to progress × AO3 word count.",
                "Novels’ worth: Words read divided by 70,000, rounded to the nearest half. Hidden under 35,000 words.",
                "Where the Words Went: Words read by each work’s first-listed fandom so the shares add up to the total (top 4, then the rest folded together).",
                "Reading and Listening: Time split by reading mode, with Read Aloud’s weighted playback rate and works listened to.",
                "Typical sitting and Pace: Typical sitting is the median sitting duration. Pace is reading-mode words divided by reading-mode time (Read Aloud is left out); character-counted languages get their own pace in characters an hour beside it.",
                "Length of What You Read: Works with a sitting in the period by AO3 word count: under 5k, 5k–50k, 50k–150k, and 150k+."
            ]
        ),
        MetricRuleSection(
            title: "Taste",
            symbol: "sparkles",
            paragraphs: [
                "Your Usual Fic: The most common status, rating, category, length band, first fandom, top relationship and top two tags among works read in the period, weighted by the By Words / By Works toggle. A field is named only when its top value covers at least 40%; needs at least 5 works.",
                "Relationships and Ship Concentration: “/” is romantic and “&” is platonic. Ship Concentration shows the share of a fandom’s words on its top relationship for fandoms with at least 4 works.",
                "Tags and Often Together: Freeform tags merge learned AO3 canonical names. Often Together lists tag pairs on at least 3 works that appear together at least 1.5 times as often as chance.",
                "Rating, Status, Category and Warnings: Works read using AO3’s labels. A work with several categories or warnings counts in each, so those two can add up to more than works read.",
                "When They Were Posted, Crossovers and Languages: Posting year from AO3’s published date with median year; crossovers resolve distinct fandoms."
            ]
        ),
        MetricRuleSection(
            title: "Habits",
            symbol: "clock.arrow.circlepath",
            paragraphs: [
                "Time of Day: Each sitting’s reading time spread across the local hours it covered, highlighting late-night reading between 1:00 and 5:00.",
                "Reading Days: Calendar shaded in four steps using the quartiles of your reading days over the last 12 months (or fixed steps under 20 reading days).",
                "Sittings: Distribution by length (< 10 m, 10–30 m, 30–60 m, 1–2 h, 2 h +), typical sitting, average chapters entered per sitting, and share ending at a chapter end. Skimmed and Peeked at the Ending appear after 20 measured chapters of pace history.",
                "From Saved to Finished: Median days from saved to first sitting (works first opened in the period) and from first sitting to first finish (complete works finished in the period).",
                "Rereads, Fandom Timeline and Stopped Reading: Rereads show share of reading time on already-finished works and top works by finishing sittings. Fandom Timeline leaves months under 5,000 words blank. Stopped Reading lists tags carried by at least 5 opened works at twice your overall stopped share."
            ]
        ),
        MetricRuleSection(
            title: "Library",
            symbol: "books.vertical",
            paragraphs: [
                "Unread and Added vs Read: Never-opened saved works (not deleted or stopped). Months to clear divides unread words by your daily pace over the last 90 days (shown as a range from 7 reading days, and one figure from 30).",
                "Where Everything Stands: Every library work lands in exactly one status, checked in order: Stopped, On Hold, Letting Chapters Stack, Finished, Caught Up, Reading, and Saved for Later.",
                "Still reading?: Asks about a work partway through with unread posted chapters after your untouched threshold. A work is never marked stopped by itself.",
                "Works in Progress and No Longer on AO3: WIPs are grouped as Active (within 6 months), Quiet (6–12 months), or Dormant (over a year). No Longer on AO3 counts confirmed last-copy and gone works only.",
                "On Finished Works, Series and Authors: Kudos left is a lower bound (browser kudos are unseen until refreshed). Series uses fetched AO3 series part counts. Authors counts AO3 author accounts, not pseuds, and leaves out orphan_account and anonymous works.",
                "How Finished Works Arrived and Found Early: Tracks where finished works came from (with each source’s finish rate) and finished works saved with under 500 kudos whose kudos have at least tripled since recording began."
            ]
        )
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CardListMetrics.interCardSpacing) {
                    ForEach(Self.sections) { section in
                        metricSection(
                            title: section.title,
                            symbol: section.symbol,
                            paragraphs: section.paragraphs
                        )
                    }
                }
                .padding(SubjectMetrics.gutter)
            }
            .appThemedScroll()
            .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
            .navigationTitle(Self.sheetTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .wrappingInlineTitle(Self.sheetTitle, isActive: dynamicTypeSize.isAccessibilitySize)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(
                        title: "Close",
                        systemImage: "xmark",
                        tint: .primary
                    ) {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        #if os(iOS)
        .modifier(ScopeSurfaceAccent())
        .presentationDragIndicator(.visible)
        #endif
    }

    private func metricSection(title: String, symbol: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.accentInk)
                    .font(.headline)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

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
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}
