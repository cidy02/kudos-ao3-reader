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
struct QueueTagSheet: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""

    private var queueTagIDs: Set<PersistentIdentifier> {
        Set(queue.tags.map(\.persistentModelID))
    }

    /// The queue's own colour, as Queue Details — which opens this — draws it.
    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue)
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
                    footnote("Tags are shared with your works, so one word means the "
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
        let isOn = queueTagIDs.contains(tag.persistentModelID)
        return SubjectFormRow(label: tag.name, action: { toggle(tag, isOn: isOn) }) {
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
        .accessibilityLabel(tag.name)
        .accessibilityValue(isOn ? "on this queue" : "not on this queue")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ tag: Tag, isOn: Bool) {
        if isOn {
            queue.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        } else {
            queue.tags.append(tag)
        }
        queue.markModified()
        context.saveBestEffort(reason: "Saving queue tags failed")
    }

    private var trimmedNewTag: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTypedTag() {
        let name = trimmedNewTag
        guard !name.isEmpty else { return }
        // Reuse an existing tag rather than inserting a second one by the same
        // name — `Tag.name` is unique, and a duplicate throws.
        let tag = allTags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? {
                let created = Tag(name: name)
                context.insert(created)
                return created
            }()
        if !queue.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) {
            queue.tags.append(tag)
            queue.markModified()
        }
        context.saveBestEffort(reason: "Saving new queue tag failed")
        newTagName = ""
    }
}
