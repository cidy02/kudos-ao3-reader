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
/// **What 1j still draws that this does not build:** the Tags field. Queues do
/// have tags now, but adding them here would be a second tag-entry surface
/// beside `QueueTagSheet`, which already edits exactly this relationship from
/// Queue Details — so it is left to that one rather than duplicated. Its colour
/// row also ends in a dashed "+" for a custom hue; `SubjectHueSwatchRow` is the
/// app's swatch grammar and offers the palette only.
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

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @State private var options = NewQueueOptions()
    /// Read once when the sheet appears rather than in `body`: the sheet is
    /// modal, so nothing can change the count while it is open, and counting
    /// memberships on every body evaluation would walk the whole shelf.
    @State private var seedCount: Int?

    private var gutter: CGFloat { SubjectMetrics.gutter }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    SubjectHueSwatchRow(selection: $hue, fallbackHue: previewHue)
                        .pageBodyRow(top: 10, gutter: gutter)
                    footnote(hue == nil
                        ? "Without a colour, the queue takes one from its name — and "
                            + "changes it if you rename it."
                        : "Set once, so renaming the queue keeps its colour.")
                }

                Section {
                    groupLabel("Offline")
                    offlinePanel.pageBodyRow(top: 8, gutter: gutter)
                    footnote(offlineFootnote)
                }

                Section {
                    groupLabel("Start from")
                    seedPanel.pageBodyRow(top: 8, gutter: gutter)
                }
            }
            .cardList()
            .navigationTitle("New queue")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: theme.scopePalette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { onCreate(options) }
                            .disabled(trimmedName.isEmpty)
                    }
                }
        }
        #if os(iOS)
        // Taller than .medium now: 1j's sheet carries four groups, and a medium
        // detent hid the seed step below the fold — the one decision the board
        // says you never actually want to miss.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task { seedCount = ReadingQueueService.savedForLaterSeedCount(in: context) }
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

    /// 1j's copy for this group is "On, every work you add downloads an EPUB.
    /// Off, the queue is just a list — nothing is preserved." **Neither half is
    /// true of this app yet, and the sentence that used to sit here claimed the
    /// falser one.**
    ///
    /// `SavedWork.isProtected` is `isSaved || isFavorite || isQueuedForLater ||
    /// ao3WorkID == nil`, so membership of *any* queue already exempts a work
    /// from `WorkLifecycle.freeEPUB`, toggle or no toggle. And nothing anywhere
    /// reads `ReadingQueue.keepsWorksOffline` or
    /// `WorkCollection.keepsWorksOffline` to decide anything — grepped to zero
    /// decision sites (an independent adversarial pass over the whole repo,
    /// Android included, could not find one either). The field is written by
    /// `createQueue` and `ReadingQueueSettingsView`, read back by that screen's
    /// toggle, and carried by the backup DTO — nothing else. The download side
    /// ignores it too: `ReadingQueueService.preserve` checks only
    /// `isQueuedForLater`. So the old promise ("keep their download even after
    /// they leave it") named precisely the behaviour the app does not have.
    ///
    /// ponytail: the copy now says what is true today. Making the toggle bite —
    /// letting a queue opt its works out of preservation, and keeping them
    /// preserved after they leave — changes how much disk the app uses, on three
    /// surfaces, and that is the owner's call, not a restyle's.
    private var offlineFootnote: String {
        "A work keeps its download for as long as it is in any queue. This records "
            + "your choice for this queue; Kudos does not vary preservation per "
            + "queue yet."
    }

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
                isSelected ? theme.scopePalette.accent : Color.secondary.opacity(0.4),
                lineWidth: 1.6
            )
            .frame(width: 19, height: 19)
            .overlay {
                if isSelected {
                    Circle()
                        .fill(theme.scopePalette.accent)
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
            return "An empty queue, ready to add to."
        case .savedForLater:
            guard let seedCount else { return nil }
            guard seedCount > 0 else { return "Nothing in Saved for Later to copy." }
            return "Copy all \(seedCount), in the same order, leaving them in Saved for Later."
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

    /// What the name would give this queue if no swatch is picked — the same hash
    /// `ReadingQueue.displayHue` falls back to, so the preview cannot disagree
    /// with the queue that gets created.
    private var previewHue: Double {
        CoverArt.hue(for: trimmedName)
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
    var keepsWorksOffline = false
    var seed: NewQueueSeed = .empty
}
