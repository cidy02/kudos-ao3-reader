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
/// - The colour swatch's edit affordance (mock draws a chevron). The colour
///   itself is real (see `ReadingQueueBrowserView.subjectPalette`'s note) but
///   it is *derived* from the queue's name, not a stored, independently
///   editable field — there is nothing a chevron here could open.
struct ReadingQueueSettingsView: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: CoverArt.hue(for: queue.displayName))
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
