import SwiftUI

// MARK: - Edit series (artboard 1br, first screen)

/// Artboard **1br** — the series form, and the reorder screen behind it.
///
/// The whole service layer for this existed and was dead: `loadSeriesForm`,
/// `loadSeriesManagePage`, `saveSeries`, `createSeries` and `reorderSeries` were
/// written, `AO3SeriesForm` and `AO3SeriesWorkRow` were complete with
/// `parameters()` ready to POST, and nothing in the app called any of it. This is
/// the screen that reaches it.
///
/// **What 1br draws that this does not build, and why:**
/// - **"Remove works"** (a row with a count, beside Reorder). There is no
///   remove-from-series call anywhere in the app — the manage page is parsed for
///   order only — so the row would open nothing. Adding one means a new write
///   endpoint, not a control.
/// - **The reorder rows' metadata line** ("4,200 words · posted Jan 2023").
///   `AO3SeriesWorkRow` carries workID, serialWorkID, title, position and
///   isDraft; `parseSeriesManagePage` reads AO3's sortable list, which prints no
///   word count and no date. Drawing either would mean inventing a figure.
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

            Section {
                SectionRuleHeader(title: "Series")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                seriesPanel.disabled(isSaving).pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "State")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                statePanel.disabled(isSaving).pageBodyRow(top: 8, gutter: gutter)
                footnote("AO3 shows Complete on the series page and in its blurb. It does not "
                    + "close the series — works can still be added.")
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

    private var seriesPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Title", arrangement: .control) {
                TextField("Title", text: $form.title).multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Creators", arrangement: .control) {
                TextField("Add a co-creator byline", text: $form.creators.coauthorByline)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Series summary", arrangement: .control) {
                TextField("Summary", text: $form.summary, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .multilineTextAlignment(.leading)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Series notes", arrangement: .control) {
                TextField("Notes", text: $form.notes, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .multilineTextAlignment(.leading)
            }
        }
        .subjectPanel()
    }

    private var statePanel: some View {
        SubjectFormRow(label: "Series is complete", arrangement: .control) {
            Toggle("", isOn: $form.isComplete).labelsHidden()
        }
        .subjectPanel()
    }

    private var worksPanel: some View {
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

    /// 1br's own sentence, with the real count in it.
    private var reorderFootnote: String {
        "A work’s place in a series is stored on the work, not the series, so reordering "
            + "writes to \(worksPhrase) — one request each."
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
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Reorder (artboard 1br, second screen)

/// 1br's reorder screen. Drag-only, with the position number kept visible
/// "because the number is the thing being written".
///
/// **Saves once, not per drag**, which is the board's own reasoning: position
/// lives on each work, so writing the order is one request per work, and a
/// failure part-way would leave the series half-ordered. `reorderSeries` already
/// does the sequential writes through request-coordinator slots; this screen's
/// job is to not start them until the reader is done dragging.
struct SeriesReorderView: View {
    let seriesID: Int
    let seriesTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var rows: [AO3SeriesWorkRow]
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
                    subtitle: "\(seriesTitle) · drag to change the reading order",
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
                Text("Position is a number on each work, so the order here is written back one "
                    + "work at a time. A failure part-way leaves the series half-ordered, which "
                    + "is why this screen saves once rather than on each drag.")
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
                Button("Save") { save() }.disabled(isSaving || !canSave)
            }
        }
    }

    /// Nothing to write when the works carry no AO3 id — `reorderSeries` matches
    /// on work ids, and a row parsed without one cannot be placed.
    private var canSave: Bool {
        rows.count > 1 && rows.allSatisfy { $0.workID != nil }
    }

    /// The number is the position *after* dragging, not the one AO3 currently
    /// holds: it is what Save will write.
    private func orderRow(_ row: AO3SeriesWorkRow, position index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(accountPalette.accent)
                .frame(minWidth: 26, alignment: .trailing)
            Text(row.title.isEmpty ? "Untitled work" : row.title)
                .font(.system(size: 14.5, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 0)
            if row.isDraft {
                SubjectChip(text: "Draft", style: .neutral, palette: accountPalette)
            }
        }
        .accessibilityElement(children: .combine)
        // Reads what the row shows: "Untitled work" for an empty title, and
        // the Draft chip, which was drawn but never spoken.
        .accessibilityLabel("\(index). \(row.title.isEmpty ? "Untitled work" : row.title)"
            + (row.isDraft ? ", Draft" : ""))
    }

    private func save() {
        guard !isSaving else { return }
        let orderedWorkIDs = rows.compactMap(\.workID)
        guard orderedWorkIDs.count == rows.count else {
            errorMessage = "Couldn’t match those works to the series."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await auth.reorderSeries(seriesID: seriesID, orderedWorkIDs: orderedWorkIDs)
                var saved = rows
                for index in saved.indices { saved[index].position = index + 1 }
                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
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

    @State private var form: AO3SeriesForm?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let form, loadedGeneration == auth.sessionGeneration {
                SeriesEditView(series: series, form: form).id(auth.sessionGeneration)
            } else if let errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Retry") { retry += 1 }
                }.padding()
            } else {
                ProgressView("Loading series…")
            }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            // Kept across reappearance — see `WritingWorkDestination` in WritingDraftsView.swift.
            if form != nil, loadedGeneration == auth.sessionGeneration { return }
            form = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded = try await auth.loadSeriesForm(seriesID: series.id)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                form = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
