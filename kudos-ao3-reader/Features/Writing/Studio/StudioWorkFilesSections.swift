import SwiftUI

extension StudioWorkFilesView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentWork.title)
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(currentWork.manuscriptStateLine(deviceName: ThisDevice.name))
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectFieldLabel(text: "Chapters", count: mergedChapters.count, style: .formGroup)

            if isLoadingAO3Chapters && mergedChapters.isEmpty {
                ProgressView("Loading chapters…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .accentFill()
            } else if let ao3ChaptersError, mergedChapters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ao3ChaptersError)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                    Button("Try Again") { reloadToken += 1 }
                        .buttonStyle(.kudosSecondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(mergedChapters.enumerated()), id: \.element.id) { index, chapter in
                        chapterRow(chapter)
                        if index < mergedChapters.count - 1 {
                            SubjectRowSeparator(inset: 44)
                        }
                    }
                    if !mergedChapters.isEmpty {
                        SubjectRowSeparator(inset: 44)
                    }
                    addChapterRow
                }
                .subjectPanel()
            }
        }
    }

    func chapterRow(_ chapter: StudioWorkChapterItem) -> some View {
        let canMoveUp = chapter.localChapterID.map {
            StudioWorkFilesLogic.canMove(chapterID: $0, direction: .up, in: localChapters)
        } ?? false
        let canMoveDown = chapter.localChapterID.map {
            StudioWorkFilesLogic.canMove(chapterID: $0, direction: .down, in: localChapters)
        } ?? false

        return HStack(spacing: 10) {
            Button {
                openChapter(chapter)
            } label: {
                chapterRowLabel(chapter)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(chapter.displayTitle), \(chapter.badge.label(deviceName: ThisDevice.name)), \(chapter.metaLine)"
            )
            .accessibilityHint("Opens chapter in the editor")

            Menu {
                chapterMenuItems(chapter, canMoveUp: canMoveUp, canMoveDown: canMoveDown)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Actions for \(chapter.displayTitle)")
        }
        .padding(.horizontal, 14)
        .contextMenu {
            chapterMenuItems(chapter, canMoveUp: canMoveUp, canMoveDown: canMoveDown)
        }
        .accessibilityAction(named: "Open") { openChapter(chapter) }
        .accessibilityAction(named: "Rename") {
            guard chapter.canEditLocally else { return }
            renameChapterText = chapter.title
            renamingChapter = chapter
        }
        .accessibilityAction(named: "Duplicate") {
            guard chapter.canEditLocally else { return }
            Task { await performDuplicateChapter(chapter) }
        }
        .accessibilityAction(named: "Move Up") {
            guard canMoveUp else { return }
            Task { await performMoveChapter(chapter, direction: .up) }
        }
        .accessibilityAction(named: "Move Down") {
            guard canMoveDown else { return }
            Task { await performMoveChapter(chapter, direction: .down) }
        }
        .accessibilityAction(named: "Delete") {
            guard chapter.canEditLocally else { return }
            deletingChapter = chapter
        }
    }

    private func chapterRowLabel(_ chapter: StudioWorkChapterItem) -> some View {
        let titleColor: AnyShapeStyle = chapter.badge == .planned
            ? AnyShapeStyle(.secondaryInk)
            : AnyShapeStyle(Color.primary)
        return HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(chapter.badge == .planned ? Color.secondary : theme.accentInk)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        chapterBadgeView(chapter.badge)
                        Text(chapter.metaLine)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 6) {
                        chapterBadgeView(chapter.badge)
                        Text(chapter.metaLine)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func chapterMenuItems(
        _ chapter: StudioWorkChapterItem,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        Button {
            openChapter(chapter)
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        if chapter.canEditLocally {
            Button {
                renameChapterText = chapter.title
                renamingChapter = chapter
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                Task { await performDuplicateChapter(chapter) }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            if canMoveUp {
                Button {
                    Task { await performMoveChapter(chapter, direction: .up) }
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }

            if canMoveDown {
                Button {
                    Task { await performMoveChapter(chapter, direction: .down) }
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }

            Divider()

            Button(role: .destructive) {
                deletingChapter = chapter
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    var addChapterRow: some View {
        Button {
            Task { await addChapter() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accentInk)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text("Add Chapter")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accentInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add chapter to \(currentWork.title)")
    }

    var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectFieldLabel(
                text: "Notes",
                count: storyNotes.isEmpty ? nil : storyNotes.count,
                style: .formGroup
            )

            VStack(spacing: 0) {
                if storyNotes.isEmpty {
                    Text(
                        "Keep characters, places, and canon details on this \(ThisDevice.name). "
                            + "Story notes never go to AO3."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                } else {
                    ForEach(Array(storyNotes.enumerated()), id: \.element.id) { index, note in
                        storyNoteRow(note)
                        if index < storyNotes.count - 1 {
                            SubjectRowSeparator(inset: 44)
                        }
                    }
                }
                SubjectRowSeparator(inset: 44)
                Button {
                    noteSheetMode = .create
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.accentInk)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text("New Story Note")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.accentInk)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New story note for \(currentWork.title)")
            }
            .subjectPanel()
        }
    }

    func storyNoteRow(_ note: WritingStoryNote) -> some View {
        let kindLabel = StudioWorkFilesLogic.storyNoteKindTitle(note.kind)
        let meta = [kindLabel, note.pinned ? "Pinned" : nil, ThisDevice.name]
            .compactMap(\.self)
            .joined(separator: " · ")

        return Button {
            noteSheetMode = .edit(note)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: note.pinned ? "pin.fill" : "note.text")
                    .font(.body)
                    .foregroundStyle(note.pinned ? theme.accentInk : theme.appTheme.favoriteColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.name)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !note.detail.isEmpty {
                        Text(note.detail)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(2)
                    }
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(note.name), \(meta)")
        .contextMenu {
            Button {
                noteSheetMode = .edit(note)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                Task { await togglePin(note) }
            } label: {
                Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                Task { await deleteNote(note) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    var forAO3Section: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectFieldLabel(text: "For AO3", style: .formGroup)

            VStack(spacing: 0) {
                if let ao3WorkID = currentWork.ao3WorkID, auth.isLoggedIn {
                    NavigationLink {
                        WritingWorkDestination(workID: ao3WorkID) {
                            reloadToken += 1
                            onChanged()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.body)
                                .foregroundStyle(theme.accentInk)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Work details")
                                    .font(.body)
                                    .foregroundStyle(Color.primary)
                                Text(workDetailsSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondaryInk)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Work details on AO3, \(workDetailsSubtitle)")
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.body)
                            .foregroundStyle(.secondaryInk)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Work details")
                                .font(.body)
                                .foregroundStyle(.secondaryInk)
                            Text("Sign in to AO3 to edit tags, summary, and posting settings.")
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .subjectPanel()
        }
    }

    var workDetailsSubtitle: String {
        if let dateText = currentWork.ao3PostedWork?.dateUpdated, !dateText.isEmpty {
            return "Summary, tags, rating, notes · posted \(WorkStat.displayDate(dateText))"
        }
        if currentWork.isAO3Draft {
            return "Summary, tags, rating, notes · AO3 draft"
        }
        return "Summary, tags, rating, notes"
    }

    @ViewBuilder
    func chapterBadgeView(_ status: StudioChapterBadgeStatus) -> some View {
        let title = status.label(deviceName: ThisDevice.name)
        switch status {
        case .posted:
            SubjectStateBadge(title: title, color: theme.appTheme.statusSuccessColor)
        case .ao3Draft:
            SubjectStateBadge(title: title, color: .orange)
        case .onDevice:
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(theme.appTheme.glassFill(0.12), in: Capsule())
        case .planned:
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .overlay(
                    Capsule().strokeBorder(
                        theme.appTheme.glassStroke(0.32),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                )
        }
    }
}

/// Modal form for adding or editing a private on-device story note inside `StudioWorkFilesView`.
struct StudioStoryNoteEditorSheet: View {
    let existing: WritingStoryNote?
    let onSave: (WritingStoryNoteKind, String, String, Bool, WritingStoryNote?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var kind: WritingStoryNoteKind
    @State private var name: String
    @State private var detail: String
    @State private var pinned: Bool

    private static let allKinds: [WritingStoryNoteKind] = [
        .character, .place, .canon, .timeline, .other
    ]

    init(
        mode: StudioWorkFilesView.StoryNoteSheetMode,
        onSave: @escaping (WritingStoryNoteKind, String, String, Bool, WritingStoryNote?) -> Void
    ) {
        self.onSave = onSave
        switch mode {
        case .create:
            self.existing = nil
            _kind = State(initialValue: .character)
            _name = State(initialValue: "")
            _detail = State(initialValue: "")
            _pinned = State(initialValue: false)
        case let .edit(note):
            self.existing = note
            _kind = State(initialValue: note.kind)
            _name = State(initialValue: note.name)
            _detail = State(initialValue: note.detail)
            _pinned = State(initialValue: note.pinned)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Story Note") {
                    Picker("Kind", selection: $kind) {
                        ForEach(Self.allKinds, id: \.self) { item in
                            Text(StudioWorkFilesLogic.storyNoteKindTitle(item)).tag(item)
                        }
                    }
                    TextField(
                        "Name",
                        text: $name,
                        prompt: theme.appTheme.sepiaPrompt("Name")
                    )
                    .accessibilityLabel("Story note name")
                    TextField(
                        "Details",
                        text: $detail,
                        prompt: theme.appTheme.sepiaPrompt("Details"),
                        axis: .vertical
                    )
                    .lineLimit(3 ... 8)
                    .accessibilityLabel("Story note details")
                    Toggle("Pinned", isOn: $pinned)
                        .accentFill()
                }
                .appThemedRows()

                Section {} footer: {
                    Text("Story notes stay on this \(ThisDevice.name) and never go to AO3.")
                }
            }
            .appThemedScroll()
            .navigationTitle(existing == nil ? "New Story Note" : "Edit Story Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            kind,
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            detail.trimmingCharacters(in: .whitespacesAndNewlines),
                            pinned,
                            existing
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
