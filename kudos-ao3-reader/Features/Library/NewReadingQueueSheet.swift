import SwiftData
import SwiftUI

/// Artboard **1j**'s "New Queue" sheet — shared by Home, the queue organizer
/// (`AllReadingQueuesGridView`) and the per-queue browser
/// (`ReadingQueueBrowserView`), which each opened their own near-identical
/// plain `Form` before this.
///
/// **The colour swatches are built.** They were not, and the note that used to
/// sit here explained why: 1j wants a colour "set once instead of derived from
/// the name", every queue's colour was `CoverArt.hue(for: queue.displayName)`,
/// and storing one independently "would be a schema change, not a restyle".
/// That was the right call for a restyling task. `ReadingQueue.hue` is that
/// schema change, made by the sweep that was chartered for missing
/// functionality rather than layout, and it fixes a real defect on the way:
/// renaming a queue used to silently repaint it.
///
/// **Start from is a radio list, not a segmented pair.** The spec's own
/// one-grammar-per-choice rule sends a two-way choice to a segmented control,
/// and 1j draws two radio rows instead — so the board wins, and for a reason
/// that shows: its second row carries its own subtitle, "Copy all 12, leaving
/// them saved". A segmented pair has nowhere to put the count, and the count is
/// the thing a reader needs to decide. `savedForLaterSeedCount` reads it without
/// writing, and the row is disabled at zero rather than offering a choice that
/// would silently produce an empty queue — the same call `NewQueueSeed` already
/// made about seeding from a fandom.
///
/// **Tags and the swatch-following wash are built.** Tags are chosen here as
/// names and written by `ReadingQueueService.createQueue` through
/// `ReadingQueue.addTag`, the same lookup-before-create `QueueTagSheet` uses, so
/// nothing is created until Create. The wash, the Create tint, the radio and the
/// selected tag chips take the tapped swatch's hue.
///
/// **The colour row ends in the "More colours" well** (`SubjectHueSwatchRow`):
/// any colour, stored exactly as `ReadingQueue.colorHex` (`options.colorHex`
/// here) with its hue in `hue` beside it. A preset clears the hex.
///
/// **Edit Queue is this sheet too** (`EditReadingQueueSheet`, owner request
/// 2026-10-01): the same fields over an existing queue, saved rather than
/// created. Start from is left out — seeding only means something for a queue
/// that does not exist yet.
///
/// Chrome is `NewCollectionSheet`'s — text Cancel/Create in the navigation bar
/// rather than 1j's 34pt circle pair. The two sheets do the same job minutes
/// apart in the same tab, and one of them growing its own button vocabulary
/// would read as a bug. `AO3FilterPanel` keeps the circles, where 1au draws
/// them on a panel that has no navigation bar to put words in.
struct NewReadingQueueSheet: View {
    @Binding var name: String
    /// 1j: the colour is chosen before the name is typed, so it is committed with
    /// the queue rather than set afterwards. `nil` keeps the name-derived hue.
    @Binding var hue: Double?
    /// Owned by the sheet rather than the three hosts: they each held `name` and
    /// `hue` already, and two more bindings apiece would be three identical
    /// copies of state that only this sheet reads.
    /// Returns whether the queue was saved: false keeps the sheet open and says so.
    let onCreate: (NewQueueOptions) -> Bool
    let onCancel: () -> Void
    /// Edit Queue: title and confirm read "Edit queue" / "Save", and Start
    /// from is left out. Set through `init(name:hue:editing:onSave:onCancel:)`.
    var isEditing = false

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.title)
    private var libraryWorks: [SavedWork]
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true

    @State private var options = NewQueueOptions()
    @State private var showingNewTag = false
    @State private var newTagName = ""
    /// Read once when the sheet appears rather than in `body`: the sheet is
    /// modal, so nothing can change the count while it is open, and counting
    /// memberships on every body evaluation would walk the whole shelf.
    @State private var seedCount: Int?
    @State private var saveFailed = false
    @State private var showingAddWorks = false

    @ScaledMetric(relativeTo: .subheadline) private var nameFieldSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var seedTitleSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .caption) private var seedSubtitleSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    private var gutter: CGFloat { SubjectMetrics.gutter }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 1j: "The sheet takes a wash in whichever swatch you tap". Untapped, it
    /// keeps the app's own accent.
    private var palette: SubjectPalette {
        hue.map { theme.appTheme.subjectPalette(hue: $0, pickedHex: options.colorHex) } ?? theme.scopePalette
    }

    var body: some View {
        NavigationStack {
            List {
                if !isEditing {
                    Section {
                        groupLabel("Preview")
                        coverPreview.pageBodyRow(top: 8, gutter: gutter)
                    }
                }

                Section {
                    groupLabel("Name")
                    namePanel.pageBodyRow(top: 8, gutter: gutter)
                }

                Section {
                    groupLabel("Colour")
                    // 1j draws the swatches bare on the sheet, not on a card —
                    // they are their own shapes and a panel behind them would
                    // add an edge the board does not have.
                    SubjectHueSwatchRow(selection: $hue, pickedHex: $options.colorHex)
                        .pageBodyRow(top: 10, gutter: gutter)
                    footnote(hue == nil
                        ? "Kudos picks a colour from the queue name. Renaming it may change the colour."
                        : "Your chosen colour stays the same if you rename the queue.")
                }

                Section {
                    groupLabel("Tags")
                    tagsPanel.pageBodyRow(top: 10, gutter: gutter)
                    footnote("A tag you use here is the same tag on your works.")
                }

                Section {
                    groupLabel("Offline")
                    offlinePanel.pageBodyRow(top: 8, gutter: gutter)
                    footnote(Self.offlineFootnote)
                }

                if !isEditing {
                    Section {
                        groupLabel("Start from")
                        seedPanel.pageBodyRow(top: 8, gutter: gutter)
                    }

                    Section {
                        groupLabel("Add works")
                        addWorksRow.pageBodyRow(top: 8, gutter: gutter)
                        footnote("Chosen from your library. They are added when you create the queue.")
                    }
                }
            }
            .cardList()
            // Rows at their own padding, not the List minimum (L3-FORM-1).
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle(isEditing ? "Edit queue" : "New queue")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: palette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isEditing ? "Save" : "Create") {
                            if !onCreate(options) { saveFailed = true }
                        }
                        .disabled(trimmedName.isEmpty)
                    }
                }
        }
        // Outside the stack so the Create button, the toggle and the caret all
        // take the swatch too, not just the rows.
        .screenTint(palette)
        #if os(iOS)
        // Taller than .medium now: 1j's sheet carries four groups, and a medium
        // detent hid the seed step below the fold — the one decision the board
        // says you never actually want to miss.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            guard !isEditing else { return }
            seedCount = ReadingQueueService.savedForLaterSeedCount(in: context)
        }
        .alert("New tag", isPresented: $showingNewTag) {
            TextField("Tag", text: $newTagName)
            Button("Add", action: addNewTag)
            Button("Cancel", role: .cancel) {}
        }
        // Android's words. The sheet stays, holding what was typed, so Save can be tried again.
        .alert("Could not save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The queue wasn't saved. Try again.")
        }
        .sheet(isPresented: $showingAddWorks) {
            AddLibraryWorksSheet(
                destinationName: previewName,
                scopeName: "queue",
                candidates: { $0.filter { !$0.isQueueOnlyWork } },
                onAdd: { options.seedWorkIDs = $0.map(\.id) },
                initialSelection: Set(options.seedWorkIDs)
            )
        }
    }

    /// Placeholder until a name is typed. Create stays disabled while it is empty.
    /// The colour follows `ReadingQueue.displayHue`: the swatch, or a hue of the name.
    private var previewName: String {
        trimmedName.isEmpty ? "New queue" : trimmedName
    }

    private var previewHue: Double {
        hue ?? CoverArt.hue(for: trimmedName.isEmpty ? "Reading Queue" : trimmedName)
    }

    /// Works the sheet will add, in the order they were picked.
    private var seedWorks: [SavedWork] {
        let byID = Dictionary(libraryWorks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return options.seedWorkIDs.compactMap { byID[$0] }
    }

    private var coverPreview: some View {
        let backs = seedWorks
            .filter { !gate.isConcealed($0, enabled: hideMature) }
            .prefix(CoverStackLayout.maxBacks)
        let footer = ReadingQueueFacts.cardFooter(states: seedWorks.map(\.readingState))
        return VStack(spacing: 8) {
            StackedWorkCover(
                kind: .queue,
                name: previewName,
                hue: previewHue,
                pickedHex: options.colorHex,
                backs: Array(backs),
                size: CGSize(width: 88, height: 120)
            )
            Text(previewName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Queue cover, \(previewName), \(footer)")
    }

    private var addWorksRow: some View {
        Button {
            showingAddWorks = true
        } label: {
            HStack(spacing: 12) {
                Text(options.seedWorkIDs.isEmpty
                    ? "Choose works"
                    : "\(options.seedWorkIDs.count) selected")
                    .font(.system(size: seedTitleSize))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.effectiveTint)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add works")
        .accessibilityValue(options.seedWorkIDs.isEmpty
            ? "None selected"
            : "\(options.seedWorkIDs.count) selected")
        .accessibilityHint("Opens your library to choose works for this queue.")
    }

    /// Every existing tag, then any new names typed here that are not one yet.
    private var tagChoices: [String] {
        allTags.map(\.name) + options.tagNames.filter { !allTags.map(\.name).contains($0) }
    }

    private var tagsPanel: some View {
        FlowLayout(spacing: 7, rowSpacing: 7) {
            ForEach(tagChoices, id: \.self) { tagName in
                let isOn = options.tagNames.contains(tagName)
                Button {
                    if isOn {
                        options.tagNames.removeAll { $0 == tagName }
                    } else {
                        options.tagNames.append(tagName)
                    }
                } label: {
                    SubjectChip(text: tagName, style: isOn ? .tinted : .neutral, palette: palette)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
            Button {
                newTagName = ""
                showingNewTag = true
            } label: {
                SubjectChip(text: "+ New tag", style: .dashed)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A name matching an existing tag or one already picked, ignoring case,
    /// selects that one instead — the same rule `ReadingQueue.addTag` applies.
    private func addNewTag() {
        let typed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let name = tagChoices.first { $0.localizedCaseInsensitiveCompare(typed) == .orderedSame } ?? typed
        if !options.tagNames.contains(name) { options.tagNames.append(name) }
    }

    private func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
            .pageBodyRow(top: 18, gutter: gutter)
    }

    /// 1j draws the field alone under its label, full width — not a labelled row,
    /// which would say "Name" twice.
    private var namePanel: some View {
        TextField("Case fic pile", text: $name)
            // The title doubles as the accessibility label, so without this
            // VoiceOver reads the example placeholder as if it were the name.
            .accessibilityLabel("Name")
            .font(.system(size: nameFieldSize))
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            // Return creates too, so it reports a failed save the same way; an empty name
            // does nothing, as the disabled Create.
            .onSubmit {
                guard !trimmedName.isEmpty else { return }
                if !onCreate(options) { saveFailed = true }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .subjectPanel(cornerRadius: 11)
    }

    private var offlinePanel: some View {
        SubjectFormRow(label: "Keep works offline", arrangement: .control) {
            // Titled even though the title is hidden: `labelsHidden` hides it
            // from the eye, not from VoiceOver, and an empty title left the
            // switch announcing only "switch button, off".
            Toggle("Keep works offline", isOn: $options.keepsWorksOffline).labelsHidden().accentFill()
        }
        .subjectPanel()
    }

    /// 1j's copy for this group, and what the toggle does since T-276
    /// (`KeepOffline`, `SavedWork.isKeptOffline`).
    static let offlineFootnote = "When this is on, every work you add is downloaded for offline reading. "
        + "When it is off, the queue keeps only your list and uses no extra storage."

    private var seedPanel: some View {
        VStack(spacing: 0) {
            seedRow(.empty)
            SubjectRowSeparator(inset: 43)
            seedRow(.savedForLater)
        }
        .subjectPanel()
    }

    @ViewBuilder
    private func seedRow(_ seed: NewQueueSeed) -> some View {
        let isSelected = options.seed == seed
        let isDisabled = seed == .savedForLater && seedCount == 0
        Button {
            options.seed = seed
        } label: {
            HStack(spacing: 11) {
                radioMark(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(seed.title)
                        .font(.system(size: seedTitleSize))
                    if let subtitle = seedSubtitle(seed) {
                        Text(subtitle)
                            .font(.system(size: seedSubtitleSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(seed.title)
        // The subtitle carries the count — the thing this row exists to show —
        // and the only reason a disabled row is disabled; the label override
        // above would otherwise drop both for VoiceOver.
        .accessibilityValue(seedSubtitle(seed) ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func radioMark(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(
                isSelected ? theme.effectiveTint : Color.secondary.opacity(0.4),
                lineWidth: 1.6
            )
            .frame(width: 19, height: 19)
            .overlay {
                if isSelected {
                    Circle()
                        .fill(theme.effectiveTint)
                        .frame(width: 9, height: 9)
                }
            }
    }

    /// The count is 1j's own ("Copy all 12, leaving them saved") and the reason
    /// this is a list rather than a segmented pair. `nil` while the count is
    /// still being read, so the row never flashes a figure it has to correct.
    private func seedSubtitle(_ seed: NewQueueSeed) -> String? {
        switch seed {
        case .empty:
            // 1j gives Empty no subtitle: the word says it.
            return nil
        case .savedForLater:
            guard let seedCount else { return nil }
            guard seedCount > 0 else { return "You have no works in Saved for Later to copy." }
            return "Copy \(seedCount) work\(seedCount == 1 ? "" : "s"). They stay in Saved for Later."
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }
}

extension NewReadingQueueSheet {
    /// Edit Queue: the sheet seeded with what the queue already has.
    init(
        name: Binding<String>,
        hue: Binding<Double?>,
        editing options: NewQueueOptions,
        onSave: @escaping (NewQueueOptions) -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.init(name: name, hue: hue, onCreate: onSave, onCancel: onCancel)
        isEditing = true
        _options = State(initialValue: options)
    }
}

/// "Edit Queue" in the queue's menu and the organizer's swipe — it took
/// Rename's place, since the name is one of its fields. Owns its draft, so
/// nothing is written until Save.
struct EditReadingQueueSheet: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hue: Double?

    init(queue: ReadingQueue) {
        self.queue = queue
        _name = State(initialValue: queue.name)
        _hue = State(initialValue: queue.hue)
    }

    var body: some View {
        NewReadingQueueSheet(
            name: $name,
            hue: $hue,
            editing: NewQueueOptions(
                keepsWorksOffline: KeepOffline.queueKeeps(queue.keepsWorksOffline),
                tagNames: queue.tags.map(\.name).sorted(),
                colorHex: queue.colorHex
            ),
            onSave: { options in
                let offlineTurnedOn = ReadingQueueService.updateQueue(
                    queue, name: name, hue: hue, options: options, in: context
                )
                // `updateQueue` saved best-effort; this asks whether that stuck (a no-op when
                // it did). Unsaved, the edit is undone on the queue and the sheet keeps it.
                guard context.saveBestEffort(reason: "Saving queue changes failed") else {
                    context.rollback()
                    return false
                }
                if offlineTurnedOn {
                    ReadingQueueService.preserveMissingWorks(in: queue, context: context)
                }
                dismiss()
                return true
            },
            onCancel: { dismiss() }
        )
    }
}

/// 1j's "Start from". Two cases, because those are the two the app can honour:
/// the board also imagines seeding from a fandom, which needs the featured-fandom
/// parse 1g describes and this app does not have. Offering a third option that
/// silently produced an empty queue would be worse than not offering it.
nonisolated enum NewQueueSeed: String, CaseIterable, Identifiable, Sendable {
    case empty
    case savedForLater

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: "Empty"
        case .savedForLater: "Saved for Later"
        }
    }
}

/// What the sheet collects beyond name and colour.
nonisolated struct NewQueueOptions: Equatable, Sendable {
    /// 1j draws it on: a new queue keeps its works, as queues always have.
    var keepsWorksOffline = true
    var seed: NewQueueSeed = .empty
    /// Tag names, resolved to `Tag`s only when the queue is created.
    var tagNames: [String] = []
    /// The exact well colour (`ReadingQueue.colorHex`); the hue travels in the
    /// sheet's `hue` binding beside it.
    var colorHex: String?
    /// Library works to add when the queue is created, in pick order.
    /// Edit Queue leaves this empty: seeding only means something for a queue
    /// that does not exist yet.
    var seedWorkIDs: [UUID] = []
}
