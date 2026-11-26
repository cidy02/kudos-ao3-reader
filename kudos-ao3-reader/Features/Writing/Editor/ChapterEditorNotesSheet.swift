import SwiftUI

/// Which tab is active inside `ChapterEditorNotesSheet` (`Editor-Notes.dc.html`).
nonisolated enum ChapterEditorNotesTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case forAO3
    case storyNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forAO3: "For AO3"
        case .storyNotes: "Story Notes"
        }
    }
}

/// Native sheet opened from the editor header's Notes button and from `••• › Chapter Title,
/// Summary and Notes` (`Editor-Notes.dc.html`). `"For AO3"` edits the chapter's title,
/// summary, and beginning/end notes with AO3's live character limits; `"Story Notes"`
/// manages work-level notes stored strictly on this device via `WritingDocumentStore`.
struct ChapterEditorNotesSheet: View {
    @Binding var chapterTitle: String
    @Binding var summary: String
    @Binding var notesBefore: String
    @Binding var notesAfter: String
    let documentBridge: ChapterEditorDocumentBridge
    @State private var selectedTab: ChapterEditorNotesTab

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill

    @State private var showingNewNote = false
    @State private var newNoteKind: WritingStoryNoteKind = .character
    @State private var newNoteName = ""
    @State private var newNoteDetail = ""
    @State private var newNotePinned = false

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    init(
        chapterTitle: Binding<String>,
        summary: Binding<String>,
        notesBefore: Binding<String>,
        notesAfter: Binding<String>,
        documentBridge: ChapterEditorDocumentBridge,
        initialTab: ChapterEditorNotesTab = .storyNotes
    ) {
        _chapterTitle = chapterTitle
        _summary = summary
        _notesBefore = notesBefore
        _notesAfter = notesAfter
        self.documentBridge = documentBridge
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Which notes", selection: $selectedTab) {
                    ForEach(ChapterEditorNotesTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accentFill()
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.vertical, 10)
                .accessibilityLabel("Which notes")

                Group {
                    switch selectedTab {
                    case .forAO3:
                        forAO3Content
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
            .sheet(isPresented: $showingNewNote) {
                newStoryNoteSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
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
                    showingNewNote = true
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
                    Button("Cancel", role: .cancel) { showingNewNote = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let kind = newNoteKind
                        let name = newNoteName
                        let detail = newNoteDetail
                        let pinned = newNotePinned
                        showingNewNote = false
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
