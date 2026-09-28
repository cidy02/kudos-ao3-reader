import Foundation
import SwiftData
import SwiftUI

// MARK: - Queue details (artboard 1h)

/// Artboard **1h**'s "Queue details" screen — a settings surface for one
/// queue, pushed from `ReadingQueueBrowserView`'s overflow menu. A restyle of
/// what that toolbar already offers (rename, delete, a look at what's
/// preserved), not a new feature.
///
/// **Built:** the bare progress strip under the header (`QueueProgressStrip`);
/// "Last read", the latest of the member works' `lastReadDate`s
/// (`ReadingQueueFacts.lastRead`); TAGS as removable chips with an "Add tag"
/// chip into `QueueTagSheet` and "Manage all tags N" into `QueueTagManagerView`,
/// always shown; and a "Keep downloaded" toggle storing
/// `ReadingQueue.keepsWorksOffline` (`offlinePanel`). On (or never asked), the
/// queue's works keep their EPUBs and turning it on fetches missing ones; off,
/// the queue is a plain list (`KeepOffline`, T-276).
///
/// **The DESCRIPTION note** is `ReadingQueue.notes` (T-276), drawn in serif and
/// edited in place (`descriptionPanel`).
///
/// **The colour is editable now.** It used to be derived from the queue's name,
/// so there was nothing an edit affordance could open; `ReadingQueue.hue` is a
/// stored field and 1h's Colour row sets it. A queue that has never been given
/// one still falls back to the name hash, so nothing changed appearance.
struct ReadingQueueSettingsView: View {
    let queue: ReadingQueue
    /// "Home" or "Library" — the queue page's own origin, for the kicker.
    var originKicker = "Library"

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    /// The shared vocabulary "Manage all tags" counts.
    @Query private var allTags: [Tag]
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var showingTags = false

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue)
    }

    private var works: [SavedWork] {
        ReadingQueueService.orderedWorks(in: queue)
    }

    private var preservedWorks: [SavedWork] {
        works.filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private var preservedByteCount: Int64 {
        preservedWorks.reduce(0) { $0 + queueWorkFileSize($1.fileURL) }
    }

    private var subtitle: String {
        let count = works.count
        let base = "\(count) work\(count == 1 ? "" : "s")"
        guard count > 0 else { return base }
        let offline = preservedWorks.count == count
            ? "all kept offline"
            : "\(preservedWorks.count) kept offline"
        return "\(base) · \(offline) · \(queueByteCountString(preservedByteCount))"
    }

    private var preservedValue: String {
        preservedWorks.isEmpty ? "None" : "\(preservedWorks.count) · \(queueByteCountString(preservedByteCount))"
    }

    /// 1h.3's Colour row. Writes straight through to the model rather than holding
    /// a draft: there is no Save on this screen, and every other control here
    /// (rename, delete) commits on its own action too.
    private var colourPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubjectHueSwatchRow(
                selection: Binding(
                    get: { queue.hue },
                    set: { newValue in
                        queue.hue = newValue
                        queue.markModified()
                        context.saveBestEffort(reason: "Saving queue colour failed")
                    }
                ),
                fallbackHue: queue.displayHue
            )
            Text(queue.hue == nil
                ? "Taken from the queue's name, so renaming it changes the colour."
                : "Set on the queue, so renaming it keeps this colour.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subjectPanel()
    }

    /// 1h's "DESCRIPTION note in serif". The field is the note: it reads as the
    /// description and edits in place, writing through like Colour does — this
    /// screen has no Save. Clearing it stores "" rather than nil, so the
    /// clearing travels through sync (`KudosBackupReadingQueue.notes`).
    private var descriptionPanel: some View {
        TextField(
            "Add a description",
            text: Binding(
                get: { queue.notes ?? "" },
                set: { newValue in
                    queue.notes = newValue
                    queue.markModified()
                    context.saveBestEffort(reason: "Saving queue description failed")
                }
            ),
            axis: .vertical
        )
        .font(.system(.body, design: .serif))
        .accessibilityLabel("Description")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subjectPanel()
    }

    /// 1h's queue tags: "the tags as removable chips ... with Manage all tags as
    /// the way out to the shared vocabulary". × takes a tag off this queue only
    /// (`ReadingQueue.removeTag`, `QueueTagSheet`'s own path); "Add tag" opens
    /// that sheet. 1i's organizer rail filters on the same relationship.
    private var tagsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(queue.tags.sorted { $0.name < $1.name }) { tag in
                    Button {
                        queue.removeTag(tag)
                        context.saveBestEffort(reason: "Removing queue tag failed")
                    } label: {
                        SubjectChip(text: tag.name, style: .tinted, trailingImage: "xmark", palette: palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(tag.name)")
                }
                Button {
                    showingTags = true
                } label: {
                    SubjectChip(text: "Add tag", style: .dashed, systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            SubjectRowSeparator()
            SubjectFormRow(label: "Manage all tags", value: "\(allTags.count)", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Manage all tags") {
                    QueueTagManagerView(queue: queue)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: ReadingQueueFacts.kicker(origin: originKicker, isDetails: true),
                    title: queue.displayName,
                    subtitle: subtitle,
                    palette: palette
                )
                .pageBodyRow(top: 20, gutter: 0)
                if !works.isEmpty {
                    QueueProgressStrip(
                        progress: ReadingQueueFacts.progress(of: works.map(\.readingState)),
                        palette: palette
                    )
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.headerGutter)
                }
            }

            Section {
                SubjectFieldLabel(text: "Description", style: .formGroup)
                    .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                descriptionPanel
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            Section {
                SubjectFieldLabel(text: "Details", style: .formGroup)
                    .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                detailsPanel
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            Section {
                SubjectFieldLabel(text: "Colour", style: .formGroup)
                    .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                colourPanel
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            Section {
                SubjectFieldLabel(text: "Tags", style: .formGroup)
                    .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                tagsPanel
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            Section {
                SubjectFieldLabel(text: "Offline and order", style: .formGroup)
                    .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                offlinePanel
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                // 1j's sentence, true since T-276 (`KeepOffline`).
                Text(NewReadingQueueSheet.offlineFootnote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            if queue.kind == .custom {
                Section {
                    SubjectFieldLabel(text: "Rename & Delete", style: .formGroup)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                    managementPanel
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .sheet(isPresented: $showingTags) { QueueTagSheet(queue: queue) }
        #if os(macOS)
        .navigationTitle(queue.displayName)
        #endif
        .alert("Rename Queue", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    queue.name = trimmed
                    queue.markModified()
                    context.saveBestEffort(reason: "Saving queue rename failed")
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete “\(queue.displayName)”?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                PreservedWorkService.softDelete(queue, in: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The queue moves to Recently Deleted for 90 days, with everything in it "
                    + "intact. Works stay in Kudos either way."
            )
        }
    }

    /// "Order" is real, if thin: every queue's works are in the manual,
    /// drag-reordered order `ReadingQueueBrowserView`'s Reorder mode writes —
    /// there is no other sort mode to name here. "Preserved" is the same
    /// figure `ReadingQueueStorageView` shows app-wide, scoped to this queue.
    /// 1h's Queue Details asks for "offline with its consequence spelled out",
    /// and 1i for the pin that lifts a queue above the rest. The consequence is
    /// spelled out because it is the whole point of the setting: queued works
    /// already keep their EPUB, so what this changes is what happens when the
    /// work leaves the queue.
    private var offlinePanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Pin to the top", arrangement: .control) {
                Toggle("Pin to the top", isOn: Binding(
                    get: { queue.isPinned },
                    set: { isOn in
                        queue.isPinned = isOn
                        queue.markModified()
                        context.saveBestEffort(reason: "Saving queue pin failed")
                    }
                ))
                .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Keep downloaded", arrangement: .control) {
                Toggle("Keep downloaded", isOn: Binding(
                    // nil is "never asked", and a never-asked queue keeps its
                    // works downloaded as queues always did (`KeepOffline`).
                    get: { KeepOffline.queueKeeps(queue.keepsWorksOffline) },
                    set: { isOn in
                        queue.keepsWorksOffline = isOn
                        queue.markModified()
                        context.saveBestEffort(reason: "Saving queue offline setting failed")
                        if isOn { fetchMissingDownloads() }
                    }
                ))
                .labelsHidden()
            }
        }
        .subjectPanel()
    }

    /// Turning Keep downloaded on fetches the works still missing their EPUB,
    /// one at a time through the paced client (`ReadingQueueService.preserve`).
    /// Only this tap starts it: nothing polls.
    private func fetchMissingDownloads() {
        let missing = works.filter { !$0.hasEPUB && !$0.isPendingDeletion }
        guard !missing.isEmpty else { return }
        Task {
            for work in missing {
                try? await ReadingQueueService.preserve(work, in: context)
            }
        }
    }

    private var detailsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Order", value: "Manual")
            SubjectRowSeparator()
            SubjectFormRow(label: "Preserved", value: preservedValue)
            // 1h: "Last read · 2 hours ago". Omitted for a queue nobody has read in.
            if let lastRead = ReadingQueueFacts.lastRead(works.map(\.lastReadDate)) {
                SubjectRowSeparator()
                SubjectFormRow(label: "Last read", value: lastRead.formatted(.relative(presentation: .named)))
            }
        }
        .subjectPanel()
    }

    private var managementPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Rename",
                value: queue.name,
                showsDisclosure: true,
                action: {
                    renameText = queue.name
                    showingRename = true
                }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Delete Queue",
                value: "",
                isDestructive: true,
                action: { confirmDelete = true }
            )
        }
        .subjectPanel()
    }
}
