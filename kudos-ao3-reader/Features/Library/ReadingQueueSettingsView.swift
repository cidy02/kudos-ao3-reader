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
    var onShowOnlyTag: (Tag) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    /// The shared vocabulary "Manage all tags" counts.
    @Query private var allTags: [Tag]
    @State private var showingTags = false

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue, pickedHex: queue.colorHex)
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
        .font(.custom("New York", size: 16, relativeTo: .body))
        .accessibilityLabel("Description")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 1h's queue tags: "the tags as removable chips ... with Manage all tags as
    /// the way out to the shared vocabulary". × takes a tag off this queue only
    /// (`ReadingQueue.removeTag`, `QueueTagSheet`'s own path); "Add tag" opens
    /// that sheet. 1i's organizer rail filters on the same relationship.
    private var tagsPanel: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(queue.tags.sorted { $0.name < $1.name }) { tag in
                Button {
                    queue.removeTag(tag)
                    context.saveBestEffort(reason: "Removing queue tag failed")
                } label: {
                    queueDetailChip(tag.name, style: .tinted, trailingImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(tag.name)")
            }
            Button {
                showingTags = true
            } label: {
                queueDetailChip("Add tag", style: .dashed, systemImage: "plus")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    let progress = ReadingQueueFacts.progress(of: works.map(\.readingState))
                    // 1h.3 repeats the queue page's strip and its legend.
                    VStack(alignment: .leading, spacing: 7) {
                        QueueProgressStrip(progress: progress, palette: palette)
                        Text(ReadingQueueFacts.legend(progress, offlineCount: preservedWorks.count))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
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
                SubjectFieldLabel(text: "Tags", style: .formGroup)
                    .pageBodyRow(top: 24, gutter: SubjectMetrics.gutter)
                tagsPanel
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            Section {
                SubjectFieldLabel(text: "Details", style: .formGroup)
                    .pageBodyRow(top: 22, gutter: SubjectMetrics.gutter)
                detailsPanel
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                Text(
                    "Turning offline off leaves the queue as a plain list — "
                        + "nothing is preserved and it stops counting against storage."
                )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .pageBodyRow(top: 2, gutter: SubjectMetrics.gutter + 6)
            }

            Section {
                manageTagsPanel
                    .pageBodyRow(top: 16, gutter: SubjectMetrics.gutter)
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: palette, washHeight: 620)
        .sheet(isPresented: $showingTags) { QueueTagSheet(queue: queue) }
        #if os(macOS)
        .navigationTitle(queue.displayName)
        #endif
        .screenTint(palette)
    }

    /// 1h.3/1h.4's single Details card. The header and legend already report
    /// the preserved count, so it is not repeated as another row here.
    private var detailsPanel: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(SubjectHueSwatches.all) { swatch in
                    Button {
                        setHue(swatch.hue)
                    } label: {
                        if SubjectHueSwatches.matches(swatch, queue.hue) {
                            Label(swatch.name, systemImage: "checkmark")
                        } else {
                            Text(swatch.name)
                        }
                    }
                }
                Divider()
                Button("From queue name") { setHue(nil) }
            } label: {
                SubjectFormRow(label: "Colour", showsDisclosure: true) {
                    Circle()
                        // A picked "+" colour shows as itself.
                        .fill(queue.colorHex.flatMap(Color.init(hex:))
                            ?? themeManager.appTheme.subjectPalette(hue: queue.displayHue).accent)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colour")
            SubjectRowSeparator()
            SubjectFormRow(label: "Keep works offline", arrangement: .control) {
                Toggle("Keep works offline", isOn: Binding(
                    // nil is "never asked", and a never-asked queue keeps its
                    // works downloaded as queues always did (`KeepOffline`).
                    get: { KeepOffline.queueKeeps(queue.keepsWorksOffline) },
                    set: { isOn in
                        queue.keepsWorksOffline = isOn
                        queue.markModified()
                        context.saveBestEffort(reason: "Saving queue offline setting failed")
                        if isOn { ReadingQueueService.preserveMissingWorks(in: queue, context: context) }
                    }
                ))
                .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Order", value: "Manual")
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Last read",
                value: ReadingQueueFacts.lastRead(works.map(\.lastReadDate))?
                    .formatted(.relative(presentation: .named)) ?? "Never"
            )
        }
        .subjectPanel()
    }

    private var manageTagsPanel: some View {
        SubjectFormRow(label: "Manage all tags", value: "\(allTags.count)", showsDisclosure: true)
            .subjectPanel()
            .subjectRowNavigation(accessibilityLabel: "Manage all tags") {
                QueueTagManagerView(queue: queue, onShowOnlyTag: onShowOnlyTag)
            }
    }

    private func queueDetailChip(
        _ text: String,
        style: SubjectChip.Style,
        systemImage: String? = nil,
        trailingImage: String? = nil
    ) -> some View {
        SubjectChip(
            text: text,
            style: style,
            systemImage: systemImage,
            trailingImage: trailingImage,
            palette: palette,
            fontWeight: .medium,
            horizontalPadding: 12,
            verticalPadding: 8
        )
    }

    /// A preset or the name hash replaces a picked "+" colour.
    private func setHue(_ hue: Double?) {
        queue.hue = hue
        queue.colorHex = nil
        queue.markModified()
        context.saveBestEffort(reason: "Saving queue colour failed")
    }
}
