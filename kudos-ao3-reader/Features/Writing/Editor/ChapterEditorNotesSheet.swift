import SwiftUI

/// Which tab is active inside `ChapterEditorNotesSheet` (`Editor-Notes.dc.html`,
/// `Editor-Annotations.dc.html`).
nonisolated enum ChapterEditorNotesTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case forAO3
    case chapterNotes
    case storyNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forAO3: "For AO3"
        case .chapterNotes: "In Chapter"
        case .storyNotes: "Story Notes"
        }
    }
}

/// Native sheet opened from the editor header's Notes button, the status line's note/TK count,
/// and `••• › Chapter Title, Summary and Notes` (`Editor-Notes.dc.html`,
/// `Editor-Annotations.dc.html`). `"For AO3"` edits the chapter's title, summary, and
/// beginning/end notes with AO3's live character limits; `"In Chapter"` lists this chapter's
/// private anchored notes and TK markers; `"Story Notes"` manages work-level notes stored
/// strictly on this device via `WritingDocumentStore`.
struct ChapterEditorNotesSheet: View {
    @Binding var chapterTitle: String
    @Binding var summary: String
    @Binding var notesBefore: String
    @Binding var notesAfter: String
    let documentBridge: ChapterEditorDocumentBridge
    let chapterHTML: String
    let onAnnotationsChanged: (() -> Void)?
    @State private var selectedTab: ChapterEditorNotesTab

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var activeSubSheet: ActiveSubSheet?
    @State private var newNoteKind: WritingStoryNoteKind = .character
    @State private var newNoteName = ""
    @State private var newNoteDetail = ""
    @State private var newNotePinned = false

    private enum ActiveSubSheet: Identifiable {
        case newStoryNote
        case annotation(WritingAnnotation, paragraphNumber: Int?)

        var id: String {
            switch self {
            case .newStoryNote: "new-story-note"
            case let .annotation(annotation, _): "annotation-\(annotation.id.uuidString)"
            }
        }
    }

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    init(
        chapterTitle: Binding<String>,
        summary: Binding<String>,
        notesBefore: Binding<String>,
        notesAfter: Binding<String>,
        documentBridge: ChapterEditorDocumentBridge,
        chapterHTML: String = "",
        initialTab: ChapterEditorNotesTab = .storyNotes,
        onAnnotationsChanged: (() -> Void)? = nil
    ) {
        _chapterTitle = chapterTitle
        _summary = summary
        _notesBefore = notesBefore
        _notesAfter = notesAfter
        self.documentBridge = documentBridge
        self.chapterHTML = chapterHTML
        self.onAnnotationsChanged = onAnnotationsChanged
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.vertical, 10)

                Group {
                    switch selectedTab {
                    case .forAO3:
                        forAO3Content
                    case .chapterNotes:
                        chapterNotesContent
                    case .storyNotes:
                        storyNotesContent
                    }
                }
            }
            .background(appTheme.cardBackdrop.ignoresSafeArea())
            .navigationTitle("Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
            .sheet(item: $activeSubSheet) { sheet in
                switch sheet {
                case .newStoryNote:
                    newStoryNoteSheet
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                case let .annotation(annotation, paragraphNumber):
                    ChapterEditorAnnotationDetailSheet(
                        annotation: annotation,
                        paragraphNumber: paragraphNumber,
                        onToggleResolved: { target, resolved in
                            let updated = await documentBridge.setAnnotationResolved(
                                target,
                                resolved: resolved
                            )
                            onAnnotationsChanged?()
                            return updated
                        },
                        onSaveText: { target, text in
                            var edited = target
                            edited.text = text
                            let updated = await documentBridge.updateAnnotation(edited)
                            onAnnotationsChanged?()
                            return updated
                        },
                        onDelete: { target in
                            _ = await documentBridge.deleteAnnotation(target.id)
                            onAnnotationsChanged?()
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    @ViewBuilder
    private var tabSelector: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // At AX5 a 3-segment Picker truncates tab titles on compact widths; wrap full labels.
            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(ChapterEditorNotesTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    let shape = SubjectMetrics.controlShape(dynamicTypeSize)
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                isSelected ? ThemeManager.label(on: effectiveTint) : Color.primary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 40)
                            .background(isSelected ? effectiveTint : appTheme.cardSurface, in: shape)
                            .overlay(
                                shape.strokeBorder(
                                    isSelected ? Color.clear : appTheme.cardBorder,
                                    lineWidth: 0.5
                                )
                            )
                            .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("Which notes", selection: $selectedTab) {
                ForEach(ChapterEditorNotesTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .accentFill()
            .accessibilityLabel("Which notes")
        }
    }

    private var forAO3Content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Chapter Title")
                        .font(.footnote)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondaryInk)
                        .padding(.leading, 4)
                    TextField(
                        "Chapter title (optional)",
                        text: $chapterTitle,
                        prompt: appTheme.sepiaPrompt("Chapter title (optional)")
                    )
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        appTheme.cardSurface,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(appTheme.cardBorder, lineWidth: 0.5)
                    )
                    .accessibilityLabel("Chapter title")
                }

                ChapterNotesBlocks(
                    summary: $summary,
                    notesBefore: $notesBefore,
                    notesAfter: $notesAfter,
                    placement: .all,
                    summaryExpanded: true,
                    notesBeforeExpanded: true,
                    notesAfterExpanded: true
                )
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private var storyNotesContent: some View {
        List {
            if groupedStoryNotes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Story Notes",
                        systemImage: "note.text",
                        description: Text(
                            "Keep characters, places, and canon details here. "
                                + "Story notes stay on this \(ThisDevice.name) and never go to AO3."
                        )
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedStoryNotes, id: \.kind) { group in
                    Section(Self.sectionTitle(for: group.kind)) {
                        ForEach(group.notes) { note in
                            storyNoteRow(note)
                        }
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }
            }

            Section {
                Button {
                    resetNewNoteForm()
                    activeSubSheet = .newStoryNote
                } label: {
                    Label("New Note", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accentInk)
                }
                .accessibilityLabel("New story note")
            } footer: {
                Text(
                    "Story notes belong to this work, stay on this \(ThisDevice.name), "
                        + "and never go to AO3."
                )
            }
            .listRowBackground(appTheme.appElevatedBackground)
        }
        .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
    }

    private func storyNoteRow(_ note: WritingStoryNote) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                if !note.detail.isEmpty {
                    Text(note.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await documentBridge.togglePinStoryNote(note) }
            } label: {
                Image(systemName: note.pinned ? "pin.fill" : "pin")
                    .font(.body)
                    .foregroundStyle(note.pinned ? accentInk : Color.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.pinned ? "Unpin \(note.name)" : "Pin \(note.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await documentBridge.deleteStoryNote(note.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var newStoryNoteSheet: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Picker("Category", selection: $newNoteKind) {
                        ForEach(Self.orderedNoteKinds, id: \.self) { kind in
                            Text(Self.sectionTitle(for: kind)).tag(kind)
                        }
                    }
                    TextField(
                        "Name",
                        text: $newNoteName,
                        prompt: appTheme.sepiaPrompt("Name")
                    )
                    .accessibilityLabel("Note name")
                    TextField(
                        "Details",
                        text: $newNoteDetail,
                        prompt: appTheme.sepiaPrompt("Details"),
                        axis: .vertical
                    )
                    .lineLimit(2 ... 6)
                    .accessibilityLabel("Note details")
                    Toggle("Pinned", isOn: $newNotePinned)
                        .accentFill()
                }
                .listRowBackground(appTheme.appElevatedBackground)
            }
            .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
            .background((appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("New Story Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { activeSubSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let kind = newNoteKind
                        let name = newNoteName
                        let detail = newNoteDetail
                        let pinned = newNotePinned
                        activeSubSheet = nil
                        Task {
                            await documentBridge.addStoryNote(
                                kind: kind,
                                name: name,
                                detail: detail,
                                pinned: pinned
                            )
                        }
                    }
                    .disabled(newNoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add story note")
                }
            }
        }
    }

    private var groupedStoryNotes: [(kind: WritingStoryNoteKind, notes: [WritingStoryNote])] {
        Self.orderedNoteKinds.compactMap { kind in
            let notes = documentBridge.storyNotes.filter { $0.kind == kind }
            return notes.isEmpty ? nil : (kind, notes)
        }
    }

    private func resetNewNoteForm() {
        newNoteKind = .character
        newNoteName = ""
        newNoteDetail = ""
        newNotePinned = false
    }

    private static let orderedNoteKinds: [WritingStoryNoteKind] = [
        .character, .place, .canon, .timeline, .other
    ]

    private static func sectionTitle(for kind: WritingStoryNoteKind) -> String {
        switch kind {
        case .character: "Characters"
        case .place: "Places"
        case .canon: "Canon"
        case .timeline: "Timeline"
        case .other: "Other"
        }
    }
}

// MARK: - In Chapter annotations & TKs (`Editor-Annotations.dc.html`)

extension ChapterEditorNotesSheet {
    var chapterNotesContent: some View {
        let groups = ChapterEditorAnnotationListBuilder.groups(
            from: documentBridge.annotations,
            in: chapterHTML,
            lostIDs: documentBridge.lostAnnotationIDs
        )
        return List {
            if groups.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Notes in This Chapter",
                        systemImage: "note.text",
                        description: Text(
                            "Select text in Rich Text and choose Add Note, or type TK followed by a "
                                + "space. Notes stay on this \(ThisDevice.name) and never go to AO3."
                        )
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groups) { group in
                    Section(group.kind.sectionTitle) {
                        ForEach(group.rows) { row in
                            chapterAnnotationRow(row)
                        }
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }

                Section {} footer: {
                    Text(
                        "Notes and TK markers stay on this \(ThisDevice.name) and never go to AO3."
                    )
                }
            }
        }
        .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
    }

    private func chapterAnnotationRow(_ row: ChapterEditorAnnotationRow) -> some View {
        let isResolved = row.annotation.resolvedAt != nil
        return Button {
            activeSubSheet = .annotation(row.annotation, paragraphNumber: row.paragraphNumber)
        } label: {
            annotationRowLabel(row)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint("Opens note options")
        .accessibilityAction(named: isResolved ? "Reopen" : "Resolve") {
            toggleResolve(row.annotation, resolved: !isResolved)
        }
        .accessibilityAction(named: "Delete") {
            deleteAnnotation(row.annotation)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleResolve(row.annotation, resolved: !isResolved)
            } label: {
                Label(
                    isResolved ? "Reopen" : "Resolve",
                    systemImage: isResolved ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(isResolved ? effectiveTint : appTheme.statusSuccessColor)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteAnnotation(row.annotation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                toggleResolve(row.annotation, resolved: !isResolved)
            } label: {
                Label(
                    isResolved ? "Reopen" : "Resolve",
                    systemImage: isResolved ? "arrow.uturn.backward" : "checkmark.circle"
                )
            }
            Button {
                activeSubSheet = .annotation(row.annotation, paragraphNumber: row.paragraphNumber)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteAnnotation(row.annotation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func annotationRowLabel(_ row: ChapterEditorAnnotationRow) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                ChapterEditorAnnotationBadge(kind: row.group)
                Text(row.displayText)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.locationText)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        } else {
            HStack(alignment: .center, spacing: 12) {
                ChapterEditorAnnotationBadge(kind: row.group)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayText)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Text(row.locationText)
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
    }

    private func toggleResolve(_ annotation: WritingAnnotation, resolved: Bool) {
        Task {
            _ = await documentBridge.setAnnotationResolved(annotation, resolved: resolved)
            onAnnotationsChanged?()
        }
    }

    private func deleteAnnotation(_ annotation: WritingAnnotation) {
        Task {
            _ = await documentBridge.deleteAnnotation(annotation.id)
            onAnnotationsChanged?()
        }
    }
}
