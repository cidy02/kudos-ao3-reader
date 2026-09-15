import SwiftData
import SwiftUI

/// Apply or remove your own tags across a whole selection — artboard 1af, whose
/// build note lists Tag alongside Download, Add to queue and Remove as the four
/// bulk actions that "need to accept a set rather than one work".
///
/// Tagging one work already existed, in Work Detail's My copy sheet. This is the
/// same local `SavedWork.tags` relationship applied to many, so nothing here
/// touches AO3.
///
/// A tag is shown in one of three states across the selection — on every work,
/// on some, or on none — because a bulk toggle that cannot say "some" forces the
/// reader to guess what a tap will do to the works they cannot see.
struct WorkBulkTagSheet: View {
    let works: [SavedWork]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""

    private enum Coverage {
        case all, some, none
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New tag", text: $newTagName)
                            .onSubmit(addTypedTag)
                        Button("Add", action: addTypedTag)
                            .buttonStyle(.borderless)
                            .disabled(trimmedNewTag.isEmpty)
                    }
                } footer: {
                    Text(works.count == 1
                        ? "Applies to the selected work."
                        : "Applies to all \(works.count) selected works.")
                }

                if allTags.isEmpty {
                    Section {
                        Text("No tags yet — add one above to organize your Library.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your tags") {
                        ForEach(allTags) { tag in
                            row(for: tag)
                        }
                    }
                }
            }
            .appThemedRows()
            .appThemedScroll()
            .navigationTitle("Tag")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private func row(for tag: Tag) -> some View {
        let coverage = coverage(of: tag)
        return Button {
            toggle(tag, coverage: coverage)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(for: coverage))
                    .foregroundStyle(coverage == .none ? Color.secondary : Color.accentColor)
                Text(tag.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if coverage == .some {
                    Text("some")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.name)
        .accessibilityValue(accessibilityValue(for: coverage))
    }

    private func symbol(for coverage: Coverage) -> String {
        switch coverage {
        case .all: "checkmark.circle.fill"
        case .some: "minus.circle.fill"
        case .none: "circle"
        }
    }

    private func accessibilityValue(for coverage: Coverage) -> String {
        switch coverage {
        case .all: "on every selected work"
        case .some: "on some selected works"
        case .none: "not applied"
        }
    }

    private func coverage(of tag: Tag) -> Coverage {
        let tagged = works.filter { $0.tags.contains(where: { $0.id == tag.id }) }.count
        if tagged == 0 { return .none }
        return tagged == works.count ? .all : .some
    }

    /// "Some" applies to the rest rather than clearing, which is the direction
    /// that cannot lose a tag the reader already put on a work.
    private func toggle(_ tag: Tag, coverage: Coverage) {
        if coverage == .all {
            for work in works {
                work.tags.removeAll { $0.id == tag.id }
                work.markModified()
            }
        } else {
            for work in works where !work.tags.contains(where: { $0.id == tag.id }) {
                work.tags.append(tag)
                work.markModified()
            }
        }
        context.saveBestEffort(reason: "Saving bulk tag change failed")
    }

    private var trimmedNewTag: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTypedTag() {
        let name = trimmedNewTag
        guard !name.isEmpty else { return }
        // Reuse an existing tag with the same name rather than creating a second
        // one: two tags reading identically would split the Library filter.
        let tag = allTags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? {
                let created = Tag(name: name)
                context.insert(created)
                return created
            }()
        for work in works where !work.tags.contains(where: { $0.id == tag.id }) {
            work.tags.append(tag)
            work.markModified()
        }
        context.saveBestEffort(reason: "Saving new tag failed")
        newTagName = ""
    }
}
