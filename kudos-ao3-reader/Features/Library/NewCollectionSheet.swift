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
    /// 1bk's Behaviour footnote.
    static let behaviourFootnote = "Keep downloads keeps a downloaded copy of every work in this collection. "
        + "Show on Home adds the collection above Recently Updated."

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    @State private var draftID = UUID()
    @State private var name = ""
    @State private var collectionDescription = ""
    @State private var hue: Double?
    @State private var colorHex: String?
    @State private var keepsWorksOffline = false
    @State private var showsOnHome = false
    @State private var saveFailed = false
    @State private var colorWellSession = CustomColorWellSession()

    @ScaledMetric(relativeTo: .body) private var fieldLabelSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewTitle: String {
        NewCollectionBoardCopy.previewTitle(for: name)
    }

    /// The sheet takes a wash in whichever swatch is tapped, as New queue does
    /// (owner, 2026-10-01). Untapped, it keeps the app's own accent.
    private var palette: SubjectPalette {
        hue.map { theme.appTheme.subjectPalette(hue: $0, pickedHex: colorHex) } ?? theme.scopePalette
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    previewHeaderCard
                        .pageBodyRow(top: 12, gutter: SubjectMetrics.gutter)
                }

                Section {
                    SubjectFieldLabel(text: "Name", style: .formGroup)
                        .pageBodyRow(top: 16, gutter: SubjectMetrics.gutter)
                    namePanel
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                }

                Section {
                    SubjectFieldLabel(text: "Description", style: .formGroup)
                        .pageBodyRow(top: 16, gutter: SubjectMetrics.gutter)
                    descriptionPanel
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                }

                Section {
                    appearanceAndBehaviourPanel
                        .pageBodyRow(top: 16, gutter: SubjectMetrics.gutter)
                    footnote(hue == nil
                        ? "Kudos picks a colour from the collection name. Renaming it may change the colour."
                        : "Your chosen colour stays the same if you rename the collection.")
                    // 1bk's two sentences, true since T-276: `KeepOffline`
                    // and `SavedWork.isKeptOffline`; `HomeCollectionShelves`.
                    footnote(Self.behaviourFootnote)
                }
            }
            .cardList()
            // Rows at their own padding, not the List minimum (L3-FORM-1).
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("New Collection")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .wrappingInlineTitle(
                    "New Collection",
                    isActive: dynamicTypeSize.isAccessibilitySize
                )
                .subjectScreenWash(palette: palette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ToolbarIconButton(
                            title: "Cancel",
                            systemImage: "xmark",
                            tint: .primary
                        ) {
                            colorWellSession.discard()
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create", action: create)
                            .sheetConfirmStyle()
                            .disabled(trimmedName.isEmpty)
                    }
                }
                .environment(\.customColorWellSession, colorWellSession)
        }
        // Outside the stack, as New queue: the Create button, the toggles and
        // the caret take the app tint.
        .screenTint(theme.scopePalette)
        // The same sheet chrome as New queue.
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        // As New queue: the sheet stays, holding what was typed, so Create can be tried again.
        .alert("Could not save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The collection wasn't saved. Try again.")
        }
    }

    private var raisedCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return shape
            .fill(theme.appTheme.cardSurface)
            .overlay(shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
    }

    private var previewHeaderCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            StackedWorkCover(
                kind: .collection,
                name: previewTitle,
                identity: draftID,
                hue: hue,
                pickedHex: colorHex,
                backs: [],
                size: CGSize(width: 52, height: 64)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(NewCollectionBoardCopy.previewKicker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Text(previewTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(NewCollectionBoardCopy.previewMeta)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(raisedCardBackground)
        .accessibilityElement(children: .combine)
    }

    private var namePanel: some View {
        TextField("Collection name", text: $name)
            .font(.system(size: fieldLabelSize))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(raisedCardBackground)
            .accessibilityLabel("Collection name")
    }

    private var descriptionPanel: some View {
        TextField("Optional", text: $collectionDescription, axis: .vertical)
            .font(.system(size: fieldLabelSize))
            .lineLimit(2...4)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(raisedCardBackground)
            .accessibilityLabel("Description")
    }

    private var appearanceAndBehaviourPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Colour")
                    .font(.system(size: fieldLabelSize))
                    .foregroundStyle(.primary)
                SubjectHueSwatchRow(selection: $hue, pickedHex: $colorHex)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            SubjectRowSeparator()
            SubjectFormRow(label: "Show on Home", arrangement: .control) {
                Toggle("Show on Home", isOn: $showsOnHome).labelsHidden().accentFill()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Keep downloads", arrangement: .control) {
                Toggle("Keep downloads", isOn: $keepsWorksOffline).labelsHidden().accentFill()
            }
        }
        .background(raisedCardBackground)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
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
        colorWellSession.flush()
        let collection = WorkCollection(name: trimmed)
        collection.hue = hue
        collection.colorHex = colorHex
        collection.collectionDescription = collectionDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        collection.keepsWorksOffline = keepsWorksOffline
        collection.showsOnHome = showsOnHome
        context.insert(collection)
        // Unsaved, the half-made collection is dropped so a second Create can't make two.
        guard context.saveBestEffort(reason: "Creating collection failed") else {
            context.rollback()
            saveFailed = true
            return
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var ordered: [SavedWork]

    init(collection: WorkCollection, works: [SavedWork]) {
        self.collection = collection
        self.works = works
        self._ordered = State(initialValue: works)
    }

    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .footnote) private var positionSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var authorSize: CGFloat = 13

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: collection.displayHue, pickedHex: collection.colorHex)
    }

    private var gutter: CGFloat { SubjectMetrics.gutter }

    private var contextHeaderCard: some View {
        let tileFill = themeManager.appTheme.carouselQueueTint(
            hue: collection.displayHue,
            pickedHex: collection.colorHex
        )
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Image(systemName: "square.stack")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ThemeManager.label(on: tileFill))
                .frame(width: 40, height: 40)
                .background(tileFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(NewCollectionBoardCopy.reorderKicker(workCount: ordered.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Text(collection.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(NewCollectionBoardCopy.reorderMeta)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            shape
                .fill(themeManager.appTheme.cardSurface)
                .overlay(shape.strokeBorder(themeManager.appTheme.cardBorder, lineWidth: 0.5))
        )
        .accessibilityElement(children: .combine)
    }

    /// Board `Collection-Reorder`: context card (kicker, title, drag hint) over
    /// the reorderable rows card. Keeps each row's position number and its
    /// accessibility-size stacking branch.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    contextHeaderCard
                        .pageBodyRow(top: 12, gutter: gutter)
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
                    Text("This order is used when no filter is on. Works you add later, or restore from "
                        + "Recently Deleted after tapping Done, appear at the end.")
                        .font(.system(size: footnoteSize))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .pageBodyRow(top: 8, gutter: gutter)
                }
            }
            .cardList()
            // Rows at their own padding, not the List minimum (L3-FORM-1).
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("Reorder")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .wrappingInlineTitle(
                    "Reorder",
                    isActive: dynamicTypeSize.isAccessibilitySize
                )
                .subjectScreenWash(palette: palette)
            #if os(iOS)
                .environment(\.editMode, .constant(.active))
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ToolbarIconButton(
                            title: "Cancel",
                            systemImage: "xmark",
                            tint: .primary
                        ) {
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            collection.setReadingOrder(ordered)
                            collection.markModified()
                            context.saveBestEffort(reason: "Saving collection order failed")
                            dismiss()
                        }
                        .sheetConfirmStyle()
                    }
                }
        }
            .screenTint(themeManager.scopePalette)
    }

    /// The number is the position after dragging — what Done will write — as
    /// on 1br, "because the number is the thing being written".
    private func orderRow(_ work: SavedWork, position: Int) -> some View {
        // The position over the title at the accessibility sizes: beside it the
        // title broke mid-word and was cut ("Unanswere / d Is Not U…").
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text("\(position)")
                .font(.system(size: positionSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.accent)
                // Wide enough for three digits, so titles do not jog right at
                // row 100 in a collection that can hold hundreds of works.
                .frame(minWidth: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(work.title)
                    .font(.system(size: titleSize, weight: .medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                // Unclipped, as before the redesign: a multi-creator byline is
                // how two works with the same title are told apart.
                if !work.author.isEmpty {
                    Text(work.author)
                        .font(.system(size: authorSize))
                        .foregroundStyle(.secondaryInk)
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

/// Pure board-copy formatting for `NewCollectionSheet` (`Collection-New.dc.html`)
/// and `CollectionReorderSheet` (`Collection-Reorder.dc.html`).
enum NewCollectionBoardCopy {
    static let previewKicker = "New collection"
    static let previewMeta = "No works yet · only in Kudos"
    static let reorderMeta = "Drag to set the reading order"

    static func previewTitle(for rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled collection" : trimmed
    }

    static func reorderKicker(workCount: Int) -> String {
        "Collection · \(workCount) \(workCount == 1 ? "work" : "works")"
    }
}
