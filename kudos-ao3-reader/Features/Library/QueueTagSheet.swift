import SwiftData
import SwiftUI

/// The reader's tags on one reading queue — artboard **1h**'s "the queue's tags
/// with a dashed + Tag", and what **1i**'s tag rail filters on.
///
/// The same `Tag` a work carries. 1h calls the way out of this list "Manage all
/// tags as the way out to the shared vocabulary", so a queue tagged "Comfort" and
/// a work tagged "Comfort" are one word, not two that happen to match.
///
/// Shaped like `WorkBulkTagSheet` because it is the same job over a different
/// subject, including the rule that matters most here: a tag is looked up by name
/// before it is created, because `Tag.name` is `@Attribute(.unique)` and
/// inserting a second one by the same name throws.
///
/// 1i's select mode opens it over several queues at once. A tag is then on every
/// selected queue, on some, or on none — `WorkBulkTagSheet`'s three states — and
/// a tap on "some" applies it to the rest rather than clearing it.
struct QueueTagSheet: View {
    let queues: [ReadingQueue]

    init(queue: ReadingQueue) {
        queues = [queue]
    }

    init(queues: [ReadingQueue]) {
        self.queues = queues
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""

    private enum Coverage {
        case all, some, none
    }

    private func coverage(of tag: Tag) -> Coverage {
        let tagged = queues.count(where: { queue in
            queue.tags.contains { $0.persistentModelID == tag.persistentModelID }
        })
        if tagged == 0 { return .none }
        return tagged == queues.count ? .all : .some
    }

    /// One queue's own colour, as Queue Details — which opens this — draws it;
    /// a selection of several has no one colour, so it takes the app's accent.
    private var palette: SubjectPalette {
        guard queues.count == 1, let queue = queues.first else { return themeManager.scopePalette }
        return themeManager.appTheme.subjectPalette(hue: queue.displayHue)
    }

    private var gutter: CGFloat { SubjectMetrics.gutter }

    /// 1h draws the way in — its dashed "Add tag" chip — but not this sheet, so
    /// it takes the spec's grammar for a multi-select list: a tappable row per
    /// tag with a trailing tinted checkmark, where the old sheet drew bare
    /// leading circles on white rows under a sentence-case "Your tags".
    var body: some View {
        NavigationStack {
            List {
                Section {
                    groupLabel("Add")
                    addPanel.pageBodyRow(top: 8, gutter: gutter)
                    footnote((queues.count > 1 ? "Applies to all \(queues.count) selected queues. " : "")
                        + "Tags are shared with your works, so one word means the "
                        + "same thing wherever you use it.")
                }

                Section {
                    groupLabel("Your tags")
                    if allTags.isEmpty {
                        footnote("No tags yet — add one above.")
                    } else {
                        tagPanel.pageBodyRow(top: 8, gutter: gutter)
                    }
                }
            }
            .cardList()
            .navigationTitle("Tags")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: palette)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
            .screenTint(palette)
    }

    private func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
            .pageBodyRow(top: 18, gutter: gutter)
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

    /// The same field `QueueTagManagerView` draws, so adding a tag looks the
    /// same from both ways into the vocabulary.
    private var addPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            TextField("New tag", text: $newTagName)
                .font(.system(size: 15))
                .onSubmit(addTypedTag)
            Button("Add", action: addTypedTag)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
                .buttonStyle(.plain)
                .disabled(trimmedNewTag.isEmpty)
                .opacity(trimmedNewTag.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    private var tagPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(allTags.enumerated()), id: \.element.persistentModelID) { index, tag in
                if index > 0 { SubjectRowSeparator() }
                row(for: tag)
            }
        }
        .subjectPanel()
    }

    private func row(for tag: Tag) -> some View {
        let coverage = coverage(of: tag)
        return SubjectFormRow(label: tag.name, action: { toggle(tag, coverage: coverage) }) {
            switch coverage {
            case .all:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
            case .some:
                Text("some")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
        }
        .accessibilityLabel(tag.name)
        .accessibilityValue(accessibilityValue(for: coverage))
        .accessibilityAddTraits(coverage == .all ? [.isButton, .isSelected] : .isButton)
    }

    private func accessibilityValue(for coverage: Coverage) -> String {
        switch (coverage, queues.count == 1) {
        case (.all, true): "on this queue"
        case (.all, false): "on every selected queue"
        case (.some, _): "on some selected queues"
        case (.none, true): "not on this queue"
        case (.none, false): "not on the selected queues"
        }
    }

    /// "Some" applies to the rest rather than clearing, which is the direction
    /// that cannot lose a tag the reader already put on a queue.
    private func toggle(_ tag: Tag, coverage: Coverage) {
        for queue in queues {
            let has = queue.tags.contains { $0.persistentModelID == tag.persistentModelID }
            if coverage == .all {
                queue.removeTag(tag)
            } else if !has {
                queue.tags.append(tag)
                queue.markModified()
            }
        }
        context.saveBestEffort(reason: "Saving queue tags failed")
    }

    private var trimmedNewTag: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTypedTag() {
        let added = queues.compactMap { $0.addTag(named: trimmedNewTag, in: context) }
        guard !added.isEmpty else { return }
        context.saveBestEffort(reason: "Saving new queue tag failed")
        newTagName = ""
    }
}

extension ReadingQueue {
    /// Puts the tag called `name` on this queue: the existing one when there is
    /// one (matched ignoring case), else a new one. Looked up before it is created
    /// because `Tag.name` is `@Attribute(.unique)`, and a duplicate throws. The
    /// one way in for this sheet, `QueueTagManagerView` and 1j's New queue sheet.
    /// The caller saves. Returns nil for a blank name, or when the tags could not
    /// be fetched — the lookup is the store's own (pending inserts included), not
    /// a caller's list, because a stale or failed one would insert a duplicate.
    @discardableResult
    func addTag(named rawName: String, in context: ModelContext) -> Tag? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let known = try? context.fetch(FetchDescriptor<Tag>()) else { return nil }
        let tag = known.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? {
                let created = Tag(name: name)
                context.insert(created)
                return created
            }()
        if !tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) {
            tags.append(tag)
            markModified()
        }
        return tag
    }

    /// Takes `tag` off this queue only; the tag stays in the vocabulary and on
    /// its works. The caller saves.
    func removeTag(_ tag: Tag) {
        tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        markModified()
    }
}
