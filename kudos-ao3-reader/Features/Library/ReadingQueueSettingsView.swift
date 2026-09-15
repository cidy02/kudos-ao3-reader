import Foundation
import SwiftUI

// MARK: - Queue details (artboard 1h)

/// Artboard **1h**'s "Queue details" screen — a settings surface for one
/// queue, pushed from `ReadingQueueBrowserView`'s overflow menu. A restyle of
/// what that toolbar already offers (rename, delete, a look at what's
/// preserved), not a new feature.
///
/// **What 1h draws that this does not build, and why:**
/// - A DESCRIPTION field and a TAGS chip row (plus their "Manage all tags" row
///   into artboard 1bh). `ReadingQueue` has no description or tag property, and
///   1bh itself — a "shared queue" tag manager with collaborators and
///   per-person edit rights — has no backing *at all*: this app has no
///   multi-user/collaboration model anywhere, so 1bh was not attempted in any
///   form, not even a stub.
/// - A "Keep works offline" toggle. Every work added to a queue is preserved
///   automatically (`ReadingQueueService.addAndPreserve`) — there is no opt-out
///   to show a switch for, so drawing one here would offer a choice the app
///   does not have.
/// - A "Last read" row. The queue only records when its *membership* last
///   changed (`lastMembershipChangedAt`) — not when a work inside it was last
///   opened — so a "Last read" label would print a true-looking date for a
///   fact the app does not actually track.
///
/// **The colour is editable now.** It used to be derived from the queue's name,
/// so there was nothing an edit affordance could open; `ReadingQueue.hue` is a
/// stored field and 1h's Colour row sets it. A queue that has never been given
/// one still falls back to the name hash, so nothing changed appearance.
struct ReadingQueueSettingsView: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
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

    /// 1h's queue tags. The row states the count and opens the shared-vocabulary
    /// editor; 1i's organizer rail filters on the same relationship.
    private var tagsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubjectFormRow(
                label: "Tags",
                value: queue.tags.isEmpty ? "None" : "\(queue.tags.count)",
                showsDisclosure: true
            ) {
                showingTags = true
            }
            .accessibilityAddTraits(.isButton)
            if !queue.tags.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(queue.tags.sorted { $0.name < $1.name }) { tag in
                        SubjectChip(text: tag.name, style: .tinted, palette: palette)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "Library › Queues",
                    title: queue.displayName,
                    subtitle: subtitle,
                    palette: palette
                )
                .pageBodyRow(top: 20, gutter: 0)
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
    private var detailsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Order", value: "Manual")
            SubjectRowSeparator()
            SubjectFormRow(label: "Preserved", value: preservedValue)
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
