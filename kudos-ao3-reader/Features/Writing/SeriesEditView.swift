import SwiftUI

// MARK: - Edit series (artboard 1br, first screen)

/// Artboard **1br** — the series form, and the reorder screen behind it.
///
/// The whole service layer for this existed and was dead: `loadSeriesForm`,
/// `loadSeriesManagePage`, `saveSeries`, `createSeries` and a reorder write were
/// written, `AO3SeriesForm` and `AO3SeriesWorkRow` were complete with
/// `parameters()` ready to POST, and nothing in the app called any of it. This is
/// the screen that reaches it.
///
/// **Where 1br is only partly built, and why:**
/// - **"Remove works"** removes one work at a time and never the last: AO3
///   deletes a series with its last work, and deleting a series is left to AO3
///   (below).
/// - **The reorder rows' metadata line** ("4,200 words · 12 Jan 2023") comes
///   from the series page the series screen already loaded
///   (`AO3SeriesWorkRow.attachingBlurbs`); AO3's manage page prints neither
///   figure. Opened without that page (1w's swipes), rows show the title only.
/// - **Delete is an Open-on-AO3 link, not a native action**, which is what the
///   artboard's own "Delete series **on AO3**" label says. There is no series
///   delete call either, and this is the right side of that line: deleting a
///   series is irreversible and belongs on AO3's own confirm page.
struct SeriesEditView: View {
    /// The blurb the reader tapped through. Supplies the header's counts, which
    /// the edit form itself does not carry.
    let series: AO3SeriesSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var form: AO3SeriesForm
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    init(series: AO3SeriesSummary, form: AO3SeriesForm) {
        self.series = series
        self._form = State(initialValue: form)
    }

    private var accountPalette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    /// "Water · 3 works · 118,600 words" — every part of it from the blurb, and
    /// each dropped rather than zeroed when AO3 did not print it.
    private var subtitle: String {
        var parts = [series.title]
        if let count = series.workCount {
            parts.append("\(count) work\(count == 1 ? "" : "s")")
        }
        if let words = series.words, words > 0 {
            parts.append("\(words.formatted()) words")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: "Edit series",
                    subtitle: subtitle,
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            // One `List` row per field, as AddChapterView does: summary and
            // notes each push an editor, and a `List` row fires every
            // `NavigationLink` inside it.
            Section {
                SectionRuleHeader(title: "Series")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                Group { seriesRows }.disabled(isSaving)
            }

            Section {
                SectionRuleHeader(title: "State")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                statePanel.disabled(isSaving).pageBodyRow(top: 8, gutter: gutter)
                footnote("Complete appears on the AO3 series page and its description. "
                    + "You can still add works to a complete series.")
            }

            Section {
                SectionRuleHeader(title: "Works")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                worksPanel.pageBodyRow(top: 8, gutter: gutter)
                footnote(reorderFootnote)
            }

            Section {
                SectionRuleHeader(title: "Delete")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                deletePanel.pageBodyRow(top: 8, gutter: gutter)
                footnote("Deleting the series leaves \(worksPhrase) posted and unlinks them.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.appTheme.errorColor)
                        .pageBodyRow(top: 12, gutter: gutter)
                }
            }
            if let savedMessage {
                Section {
                    Text(savedMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .pageBodyRow(top: 12, gutter: gutter)
                }
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: accountPalette)
        #if os(macOS)
        .navigationTitle("Edit series")
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isSaving || form.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Panels

    private var recoveryTarget: String { "series:\(form.seriesID ?? series.id)" }

    /// 1br: summary as a preview row, notes as "Set" + push — the same editor
    /// rows the work and chapter forms use (AO3 takes HTML in both fields).
    @ViewBuilder
    private var seriesRows: some View {
        SubjectFormRow(label: "Title", arrangement: .control, isRequired: true) {
            TextField("Title", text: $form.title).multilineTextAlignment(.trailing)
        }
        .panelSegment(0, of: 4, gutter: gutter)
        SubjectFormRow(label: "Creators", arrangement: .control) {
            TextField("Add a co-creator byline", text: $form.creators.coauthorByline)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        }
        .panelSegment(1, of: 4, gutter: gutter)
        WritingTextEditorRow(
            title: "Series summary", text: $form.summary, target: recoveryTarget, field: "summary",
            previewsText: true
        )
        .panelSegment(2, of: 4, gutter: gutter)
        WritingTextEditorRow(title: "Series notes", text: $form.notes, target: recoveryTarget, field: "notes")
            .panelSegment(3, of: 4, gutter: gutter)
    }

    private var statePanel: some View {
        SubjectFormRow(label: "Series is complete", arrangement: .control) {
            Toggle("", isOn: $form.isComplete).labelsHidden()
        }
        .subjectPanel()
    }

    private var worksPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Reorder works",
                value: "\(form.works.count)",
                showsDisclosure: true,
                isDisabled: form.works.count < 2
            )
            .subjectRowNavigation(accessibilityLabel: "Reorder works") {
                SeriesReorderView(
                    seriesID: form.seriesID ?? series.id,
                    seriesTitle: series.title,
                    rows: form.works
                ) { form.works = $0 }
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Remove works", value: "\(form.works.count)", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Remove works") {
                    SeriesRemoveWorksView(
                        seriesID: form.seriesID ?? series.id,
                        seriesTitle: series.title,
                        rows: form.works
                    ) { form.works = $0 }
                }
        }
        .subjectPanel()
    }

    private var deletePanel: some View {
        SubjectFormRow(label: "Delete series on AO3", value: "", showsDisclosure: true) {
            openURL(series.url)
        }
        .subjectPanel()
    }

    // MARK: Copy

    private var worksPhrase: String {
        let count = form.works.count
        return count == 1 ? "the work" : "the \(count) works"
    }

    /// 1br's sentence, corrected: AO3 renumbers every work from one list.
    private var reorderFootnote: String {
        "Reordering changes the saved position on \(worksPhrase). All positions are saved together."
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }

    // MARK: Save

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        savedMessage = nil
        let snapshot = form
        Task {
            do {
                let message = try await auth.saveSeries(snapshot)
                savedMessage = message
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isSaving = false
        }
    }
}

// MARK: - Reorder (artboard 1br, second screen)

/// 1br's reorder screen. Drag-only, with the position number kept visible
/// "because the number is the thing being written".
///
/// **Saves once, not per drag.** `reorderSeries` sends the whole order in one
/// request, as AO3's own manage page does, then reads the page back to check
/// it; this screen's job is to not send it until the reader is done dragging.
struct SeriesReorderView: View {
    let seriesID: Int
    let seriesTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var rows: [AO3SeriesWorkRow]
    @State private var openedGeneration: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Handed the saved order, renumbered, before this screen dismisses. The
    /// series editor that pushed it holds its own copy of the works and keeps
    /// it across reappearance, so without this a second Reorder opened on the
    /// pre-save order and a second Save wrote it back.
    let onSaved: ([AO3SeriesWorkRow]) -> Void

    init(
        seriesID: Int,
        seriesTitle: String,
        rows: [AO3SeriesWorkRow],
        onSaved: @escaping ([AO3SeriesWorkRow]) -> Void = { _ in }
    ) {
        self.seriesID = seriesID
        self.seriesTitle = seriesTitle
        self._rows = State(initialValue: rows.sorted { $0.position < $1.position })
        self.onSaved = onSaved
    }

    private var accountPalette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: "Reorder",
                    subtitle: seriesTitle,
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }

            // 1br's tree draws a `.formGroup` label here, not a rule header,
            // and one card of rows rather than a full-bleed band.
            Section {
                SubjectFieldLabel(text: "Reading order", style: .formGroup)
                    .pageBodyRow(top: 18, gutter: gutter)
            }

            Section {
                // Keyed on edge position too — see `PanelSegment`.
                ForEach(PanelSegment.keyed(rows, id: \.id), id: \.key) { segment in
                    let offset = segment.offset
                    let row = segment.element
                    orderRow(row, position: offset + 1)
                        .subjectPanelSegmentRow(
                            isFirst: offset == 0,
                            isLast: offset == rows.count - 1,
                            gutter: gutter
                        )
                }
                .onMove { indices, destination in
                    rows.move(fromOffsets: indices, toOffset: destination)
                }
            }

            Section {
                Text("Each work has a numbered position. After you arrange the list, save once to update "
                    + "the whole order on AO3 and check that it was saved.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.appTheme.errorColor)
                        .pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: accountPalette)
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        #if os(macOS)
        .navigationTitle("Reorder")
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(isSaving || rows.count < 2)
            }
        }
        .onAppear { if openedGeneration == nil { openedGeneration = auth.sessionGeneration } }
    }

    /// The number is the position *after* dragging, not the one AO3 currently
    /// holds: it is what Save will write.
    private func orderRow(_ row: AO3SeriesWorkRow, position index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(accountPalette.accent)
                .frame(minWidth: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title.isEmpty ? "Untitled work" : row.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .lineLimit(2)
                if let metadata = row.metadataText {
                    Text(metadata).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if row.isDraft {
                SubjectChip(text: "Draft", style: .neutral, palette: accountPalette)
            }
        }
        .accessibilityElement(children: .combine)
        // Reads what the row shows: "Untitled work" for an empty title, and
        // the Draft chip, which was drawn but never spoken.
        .accessibilityLabel("\(index). \(row.title.isEmpty ? "Untitled work" : row.title)"
            + (row.isDraft ? ", Draft" : "") + (row.metadataText.map { ", \($0)" } ?? ""))
    }

    private func save() {
        guard !isSaving, let generation = openedGeneration else { return }
        isSaving = true
        errorMessage = nil
        let order = rows.map(\.serialWorkID)
        Task {
            do {
                let fresh = try await AO3RequestCoordinator.shared.withSlot {
                    try await auth.reorderSeries(
                        seriesID: seriesID, orderedSerialWorkIDs: order, expectedGeneration: generation
                    )
                }
                onSaved(SeriesRemoveWorksView.keepingMetadata(of: rows, on: fresh))
                dismiss()
            } catch is CancellationError {
                errorMessage = "Your AO3 session changed, so the order was not saved."
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isSaving = false
        }
    }
}

// MARK: - Remove works (1br)

/// 1br's Remove works. One work at a time, each behind a confirmation naming
/// it, and never the last: AO3 deletes a series with its last work
/// (`SerialWork#delete_empty_series`), and deleting a series is AO3's own page.
struct SeriesRemoveWorksView: View {
    let seriesID: Int
    let seriesTitle: String

    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var rows: [AO3SeriesWorkRow]
    @State private var openedGeneration: Int?
    @State private var removing: AO3SeriesWorkRow?
    @State private var isRemoving = false
    @State private var errorMessage: String?
    /// Handed the series' works after each removal, as AO3 now lists them.
    let onChanged: ([AO3SeriesWorkRow]) -> Void

    init(
        seriesID: Int, seriesTitle: String, rows: [AO3SeriesWorkRow],
        onChanged: @escaping ([AO3SeriesWorkRow]) -> Void
    ) {
        self.seriesID = seriesID
        self.seriesTitle = seriesTitle
        self._rows = State(initialValue: rows.sorted { $0.position < $1.position })
        self.onChanged = onChanged
    }

    private var palette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account", title: "Remove works",
                    subtitle: "\(seriesTitle) · \(rows.count) work\(rows.count == 1 ? "" : "s")",
                    palette: palette, gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }
            Section {
                ForEach(PanelSegment.keyed(rows, id: \.id), id: \.key) { segment in
                    row(segment.element)
                        .subjectPanelSegmentRow(
                            isFirst: segment.offset == 0, isLast: segment.offset == rows.count - 1, gutter: gutter
                        )
                }
            }
            Section {
                Text(rows.count > 1
                    ? "A removed work stays posted and only leaves this series."
                    : "AO3 deletes a series when its last work leaves. Remove the last work by deleting "
                        + "the series on AO3.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.appTheme.errorColor)
                        .pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
        .cardList()
        .disabled(isRemoving)
        .subjectScreenWash(palette: palette)
        #if os(macOS)
        .navigationTitle("Remove works")
        #endif
        .onAppear { if openedGeneration == nil { openedGeneration = auth.sessionGeneration } }
        .alert(
            "Remove “\(Self.title(removing))” from \(seriesTitle)?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
            Button("Remove from series", role: .destructive) {
                if let removing { remove(removing) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The work stays posted on AO3.")
        }
    }

    private func row(_ row: AO3SeriesWorkRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.title(row)).font(.system(size: 14.5, weight: .medium)).lineLimit(2)
                if let metadata = row.metadataText {
                    Text(metadata).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if row.isDraft { SubjectChip(text: "Draft", style: .neutral, palette: palette) }
            if rows.count > 1 {
                Button { removing = row } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(Self.title(row)) from the series")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    static func title(_ row: AO3SeriesWorkRow?) -> String {
        guard let title = row?.title, !title.isEmpty else { return "Untitled work" }
        return title
    }

    private func remove(_ row: AO3SeriesWorkRow) {
        guard !isRemoving, let generation = openedGeneration else { return }
        isRemoving = true
        errorMessage = nil
        Task {
            do {
                let fresh = try await AO3RequestCoordinator.shared.withSlot {
                    try await auth.removeWorkFromSeries(
                        seriesID: seriesID, serialWorkID: row.serialWorkID, expectedGeneration: generation
                    )
                }
                rows = Self.keepingMetadata(of: rows, on: fresh)
                onChanged(rows)
            } catch is CancellationError {
                errorMessage = "Your AO3 session changed, so nothing was removed."
            } catch {
                errorMessage = "\(Self.title(row)) was not removed. " + UserFacingError.message(for: error)
            }
            isRemoving = false
        }
    }

    /// AO3's rows after a removal, keeping the words and date already joined.
    static func keepingMetadata(of old: [AO3SeriesWorkRow], on fresh: [AO3SeriesWorkRow]) -> [AO3SeriesWorkRow] {
        fresh.sorted { $0.position < $1.position }.map { row in
            guard let known = old.first(where: { $0.serialWorkID == row.serialWorkID }) else { return row }
            var row = row
            row.words = known.words
            row.dateText = known.dateText
            return row
        }
    }
}

// MARK: - Loader

/// Loads the series form, then hands it to `SeriesEditView`. Same shape as
/// `WritingWorkDestination`, `sessionGeneration` keying included, so signing out
/// mid-load cannot hand the next account a form built for the previous one.
struct SeriesEditDestination: View {
    @Environment(AO3AuthService.self) private var auth
    let series: AO3SeriesSummary
    /// The series page's works, when the screen opening this already loaded
    /// them — the reorder rows' words and date (1br).
    var works: [AO3WorkSummary] = []

    @State private var form: AO3SeriesForm?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let form, loadedGeneration == auth.sessionGeneration {
                SeriesEditView(series: series, form: form).id(auth.sessionGeneration)
            } else {
                WritingLoaderPage(title: "Edit series", message: errorMessage) { retry += 1 }
            }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            // Kept across reappearance — see `WritingWorkDestination` in WritingDraftsView.swift.
            if form != nil, loadedGeneration == auth.sessionGeneration { return }
            form = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                var loaded = try await auth.loadSeriesForm(seriesID: series.id)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loaded.works = AO3SeriesWorkRow.attachingBlurbs(works, to: loaded.works)
                loadedGeneration = generation
                form = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
