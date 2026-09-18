import SwiftData
import SwiftUI

/// Artboard **1bk** — creating a local collection.
///
/// A sheet rather than the bare name alert this replaced. 1bk draws two groups:
/// **Collection** (name, an optional description, colour) and **Behaviour**
/// (keep downloads, show on Home). 1bk writes each behaviour's consequence under
/// it; neither consequence is built, so the footnote says so instead.
///
/// Colour is picked here rather than assigned, which is the board's own point:
/// a hue derived from the name silently repaints a collection when it is
/// renamed. `nil` still means "take it from the name", so nothing forces a
/// choice — it just stops being the only option.
struct NewCollectionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var name = ""
    @State private var collectionDescription = ""
    @State private var hue: Double?
    @State private var keepsWorksOffline = false
    @State private var showsOnHome = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SubjectFieldLabel(text: "Collection", style: .formGroup)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                    collectionPanel
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                }

                Section {
                    SubjectFieldLabel(text: "Behaviour", style: .formGroup)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                    behaviourPanel
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                    // Both of 1bk's sentences here were untrue, and both
                    // toggles are write-only. "Keep downloads exempts these works
                    // from the cache sweep": `SavedWork.isProtected` is `isSaved
                    // || isFavorite || isQueuedForLater || ao3WorkID == nil` —
                    // collection membership is not in it — and nothing reads
                    // `WorkCollection.keepsWorksOffline`. "Show on Home adds a
                    // shelf above Recently Updated": nothing reads
                    // `showsOnHome` either; Home draws Resume, Reading Queues and
                    // Recently Updated and has no collection shelf. Both grepped
                    // to zero readers outside this sheet and the backup DTO.
                    // ponytail: the copy says what is true; wiring either toggle
                    // up is a product change and the owner's call. See
                    // `NewReadingQueueSheet.offlineFootnote` for the queue twin.
                    footnote("Kudos records both choices with the collection, but "
                        + "does not act on them yet: collection works are not kept "
                        + "offline any differently, and Home has no collection "
                        + "shelves.")
                }

                Section {
                    footnote("Local collections live on this device only. AO3 never "
                        + "sees them, and they do not sync between your devices.")
                }
            }
            .cardList()
            .navigationTitle("New collection")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: theme.scopePalette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create", action: create)
                            .disabled(trimmedName.isEmpty)
                    }
                }
        }
    }

    private var collectionPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Name", arrangement: .control) {
                TextField("Comfort reads", text: $name)
                    .multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Description", arrangement: .control) {
                TextField("Optional", text: $collectionDescription)
                    .multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            // The ring shows "derived from the name" as a visible state, so the
            // fallback has to be the hue that name would actually produce.
            SubjectHueSwatchRow(
                selection: $hue,
                fallbackHue: CoverArt.hue(for: trimmedName)
            )
            // The row insets `SubjectFormRow` gives the labels above it, so the
            // first swatch lines up under "Name" instead of touching the card.
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .subjectPanel()
    }

    private var behaviourPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Keep downloads", arrangement: .control) {
                Toggle("Keep downloads", isOn: $keepsWorksOffline).labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Show on Home", arrangement: .control) {
                Toggle("Show on Home", isOn: $showsOnHome).labelsHidden()
            }
        }
        .subjectPanel()
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
    }

    /// The description is stored on `collectionDescription`, which already
    /// existed to keep Android's field alive across a restore. 1bk gives it a
    /// UI, so it stops being parity-only storage.
    ///
    /// Both toggles are written as real choices — the reader was asked here, so
    /// "off" is an answer rather than the absence of one.
    private func create() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        let collection = WorkCollection(name: trimmed)
        collection.hue = hue
        collection.collectionDescription = collectionDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        collection.keepsWorksOffline = keepsWorksOffline
        collection.showsOnHome = showsOnHome
        context.insert(collection)
        context.saveBestEffort(reason: "Creating collection failed")
        dismiss()
    }
}

/// Artboard **1bk**'s "Reorder works", from its Contents group.
///
/// Drag-to-reorder over the collection's own works, written to
/// `WorkCollection.workOrderRaw`. Offered only when there is more than one work,
/// because reordering one thing is a control that cannot do anything.
///
/// The order is committed on Done rather than on every drag: a collection can
/// hold hundreds of works, and rewriting the whole order string on each frame of
/// a drag would be a save per frame.
struct CollectionReorderSheet: View {
    let collection: WorkCollection
    let works: [SavedWork]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var ordered: [SavedWork]

    init(collection: WorkCollection, works: [SavedWork]) {
        self.collection = collection
        self.works = works
        self._ordered = State(initialValue: works)
    }

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: collection.displayHue)
    }

    private var gutter: CGFloat { SubjectMetrics.gutter }

    /// 1bk draws only the way in ("Reorder works · 14 ›"); the reorder screen
    /// itself is 1br's, which `SeriesReorderView` already builds — header block,
    /// a "Reading order" group, rows carrying the position they will be saved
    /// at, a note under them. This follows it, except that the group heading is
    /// the `.formGroup` label 1br's tree draws rather than that view's rule.
    ///
    /// Titles and creators are shown exactly as before. Whether a mature work's
    /// title belongs behind `PrivacyGate` here, as it is elsewhere, is an open
    /// question for the owner — not decided by a restyle.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    SubjectHeaderBlock(
                        kicker: "Library › Collections",
                        title: "Reorder",
                        subtitle: "\(collection.name) · drag to change the reading order",
                        palette: palette,
                        gutter: gutter
                    )
                    .pageBodyRow(top: 20, gutter: 0)
                }

                Section {
                    SubjectFieldLabel(text: "Reading order", style: .formGroup)
                        .pageBodyRow(top: 18, gutter: gutter)
                }

                Section {
                    // Enumerated so each row gets its position without a
                    // `firstIndex` search — per row, per frame of a drag, over a
                    // collection that can hold hundreds of works.
                    // Keyed on edge position too — see `PanelSegment`.
                    ForEach(PanelSegment.keyed(ordered, id: \.id), id: \.key) { segment in
                        let offset = segment.offset
                        let work = segment.element
                        orderRow(work, position: offset + 1)
                            .subjectPanelSegmentRow(
                                isFirst: offset == 0,
                                isLast: offset == ordered.count - 1,
                                gutter: gutter
                            )
                    }
                    .onMove { indices, destination in
                        ordered.move(fromOffsets: indices, toOffset: destination)
                    }
                }

                Section {
                    // True of `inReadingOrder` and `setReadingOrder` as written,
                    // and no more. Only Done writes `workOrderRaw` (and backup
                    // restore), so a work removed or deleted AFTER this keeps its
                    // slot and returns to it — an earlier draft of this note said
                    // restored works "join at the end", which was only true of
                    // works already in Recently Deleted when Done was tapped (they
                    // are not in this list, so Done drops their place). Ids
                    // missing from the order sort after it. An active Library
                    // filter re-sorts (`LibraryFilters.apply`).
                    Text("The collection lists its works in this order unless a filter "
                        + "is on. Works not in it — added later, or in Recently "
                        + "Deleted when you tap Done — appear after it.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .pageBodyRow(top: 8, gutter: gutter)
                }
            }
            .cardList()
            .navigationTitle("Reorder works")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: palette)
            #if os(iOS)
                .environment(\.editMode, .constant(.active))
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            collection.setReadingOrder(ordered)
                            collection.markModified()
                            context.saveBestEffort(reason: "Saving collection order failed")
                            dismiss()
                        }
                    }
                }
        }
    }

    /// The number is the position after dragging — what Done will write — as
    /// on 1br, "because the number is the thing being written".
    private func orderRow(_ work: SavedWork, position: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.accent)
                // Wide enough for three digits, so titles do not jog right at
                // row 100 in a collection that can hold hundreds of works.
                .frame(minWidth: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(work.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                // Unclipped, as before the redesign: a multi-creator byline is
                // how two works with the same title are told apart.
                if !work.author.isEmpty {
                    Text(work.author)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        // The creator is read too: the combined label it replaces did read it,
        // and it is what tells two same-titled works apart while dragging.
        .accessibilityLabel(work.author.isEmpty
            ? "\(position). \(work.title)"
            : "\(position). \(work.title), \(work.author)")
    }
}
