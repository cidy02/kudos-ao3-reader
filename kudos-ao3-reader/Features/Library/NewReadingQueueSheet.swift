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
/// **The colour row's dashed "+" is built** in `SubjectHueSwatchRow`: the system
/// colour picker, kept as a hue like the swatches.
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
    let onCreate: (NewQueueOptions) -> Void
    let onCancel: () -> Void
    /// Edit Queue: title and confirm read "Edit queue" / "Save", and Start
    /// from is left out. Set through `init(name:hue:editing:onSave:onCancel:)`.
    var isEditing = false

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var options = NewQueueOptions()
    @State private var showingNewTag = false
    @State private var newTagName = ""
    /// Read once when the sheet appears rather than in `body`: the sheet is
    /// modal, so nothing can change the count while it is open, and counting
    /// memberships on every body evaluation would walk the whole shelf.
    @State private var seedCount: Int?

    private var gutter: CGFloat { SubjectMetrics.gutter }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 1j: "The sheet takes a wash in whichever swatch you tap". Untapped, it
    /// keeps the app's own accent.
    private var palette: SubjectPalette {
        hue.map { theme.appTheme.subjectPalette(hue: $0) } ?? theme.scopePalette
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    groupLabel("Name")
                    namePanel.pageBodyRow(top: 8, gutter: gutter)
                }

                Section {
                    groupLabel("Colour")
                    // 1j draws the swatches bare on the sheet, not on a card —
                    // they are their own shapes and a panel behind them would
                    // add an edge the board does not have.
                    SubjectHueSwatchRow(selection: $hue)
                        .pageBodyRow(top: 10, gutter: gutter)
                    footnote(hue == nil
                        ? "Without a colour, the queue takes one from its name — and "
                            + "changes it if you rename it."
                        : "Set once, so renaming the queue keeps its colour.")
                }

                Section {
                    groupLabel("Tags")
                    tagsPanel.pageBodyRow(top: 10, gutter: gutter)
                    footnote("Tags are shared with the ones already on works, so one word "
                        + "means the same thing in both places.")
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
                        Button(isEditing ? "Save" : "Create") { onCreate(options) }
                            .disabled(trimmedName.isEmpty)
                    }
                }
        }
        // Outside the stack so the Create button, the toggle and the caret all
        // take the swatch too, not just the rows.
        .tint(palette.tint)
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
            .font(.system(size: 16))
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            .onSubmit { onCreate(options) }
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
            Toggle("Keep works offline", isOn: $options.keepsWorksOffline).labelsHidden()
        }
        .subjectPanel()
    }

    /// 1j's copy for this group, and what the toggle does since T-276
    /// (`KeepOffline`, `SavedWork.isKeptOffline`).
    static let offlineFootnote = "On, every work you add downloads an EPUB. "
        + "Off, the queue is just a list — nothing is preserved and nothing counts against storage."

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
                        .font(.system(size: 14.5))
                    if let subtitle = seedSubtitle(seed) {
                        Text(subtitle)
                            .font(.system(size: 11.5))
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
                isSelected ? palette.accent : Color.secondary.opacity(0.4),
                lineWidth: 1.6
            )
            .frame(width: 19, height: 19)
            .overlay {
                if isSelected {
                    Circle()
                        .fill(palette.accent)
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
            guard seedCount > 0 else { return "Nothing in Saved for Later to copy." }
            return "Copy all \(seedCount), leaving them saved"
        }
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
}

extension NewReadingQueueSheet {
    /// Edit Queue: the sheet seeded with what the queue already has.
    init(
        name: Binding<String>,
        hue: Binding<Double?>,
        editing options: NewQueueOptions,
        onSave: @escaping (NewQueueOptions) -> Void,
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
                tagNames: queue.tags.map(\.name).sorted()
            ),
            onSave: { options in
                if ReadingQueueService.updateQueue(queue, name: name, hue: hue, options: options, in: context) {
                    ReadingQueueService.preserveMissingWorks(in: queue, context: context)
                }
                dismiss()
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
}
