import SwiftUI

/// Works written on this device in the Rich Text beta, with no AO3 account needed (T-576, `WritingDocumentStore`).
/// Reached from Account → Drafts on This Device while the Rich Text flag is on. A work opens in
/// `LocalChapterEditorScreen`; New Draft starts one. Above the works sits the Ideas inbox (T-576e):
/// thoughts caught with New Idea that aren't in a work yet.
struct LocalDraftsView: View {
    let store: WritingDocumentStore
    let inbox: IdeaInbox

    @State private var works: [WritingWork] = []
    @State private var ideas: [CapturedIdea] = []
    @State private var ideaToMove: CapturedIdea?
    @State private var busyIdeaIDs: Set<UUID> = []
    @State private var ideasLoadError: String?
    @State private var actionError: String?
    @State private var loadError: String?
    @State private var hasLoaded = false

    init(
        store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot),
        inbox: IdeaInbox = .shared
    ) {
        self.store = store
        self.inbox = inbox
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LocalChapterEditorScreen(store: store)
                } label: {
                    Label("New Draft", systemImage: "square.and.pencil")
                }
            } footer: {
                Text("Drafts here are saved on this device. Post them to AO3 when you're ready.")
            }

            if let ideasLoadError {
                Section("Ideas") {
                    Text(ideasLoadError)
                        .foregroundStyle(.secondary)
                }
            } else if !ideas.isEmpty {
                Section("Ideas") {
                    ForEach(ideas) { idea in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.text).lineLimit(3)
                            Text(idea.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions(edge: .trailing) { ideaActions(idea) }
                        .contextMenu { ideaActions(idea) }
                    }
                }
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
            } else if hasLoaded, works.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No drafts yet",
                        systemImage: "doc.richtext",
                        description: Text("Start one with New Draft.")
                    )
                }
            } else if !works.isEmpty {
                Section("Drafts") {
                    ForEach(works, id: \.id) { work in
                        NavigationLink {
                            LocalChapterEditorScreen(workID: work.id, initialWorkTitle: work.title, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(work.title.isEmpty ? "Untitled" : work.title)
                                Text(Self.detail(for: work))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .navigationTitle("Drafts on This Device")
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(
            "Add to Work",
            isPresented: Binding(
                get: { ideaToMove != nil },
                set: { if !$0 { ideaToMove = nil } }
            ),
            titleVisibility: .visible,
            presenting: ideaToMove
        ) { idea in
            ForEach(works, id: \.id) { work in
                Button(work.title.isEmpty ? "Untitled" : work.title) { move(idea, to: work) }
            }
        } message: { _ in
            Text("It becomes a story note in that work.")
        }
        .alert(
            actionError ?? "",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func ideaActions(_ idea: CapturedIdea) -> some View {
        Button(role: .destructive) {
            delete(idea)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        if !works.isEmpty {
            Button {
                ideaToMove = idea
            } label: {
                Label("Add to Work…", systemImage: "text.badge.plus")
            }
        }
    }

    static func detail(for work: WritingWork) -> String {
        let chapters = work.chapterOrder.count
        let count = chapters == 1 ? "1 chapter" : "\(chapters) chapters"
        return "\(count) · edited \(work.updatedAt.formatted(.relative(presentation: .named)))"
    }

    private func delete(_ idea: CapturedIdea) {
        guard !busyIdeaIDs.contains(idea.id) else { return }
        busyIdeaIDs.insert(idea.id)
        Task {
            defer { busyIdeaIDs.remove(idea.id) }
            do {
                try await inbox.remove(id: idea.id)
                await reload()
            } catch {
                actionError = "Couldn't delete this idea."
            }
        }
    }

    private func move(_ idea: CapturedIdea, to work: WritingWork) {
        guard !busyIdeaIDs.contains(idea.id) else { return }
        busyIdeaIDs.insert(idea.id)
        Task {
            defer { busyIdeaIDs.remove(idea.id) }
            do {
                try await NewIdeaSaver(store: store, inbox: inbox).move(idea, toWork: work.id)
                await reload()
            } catch {
                actionError = "Couldn't add this idea to that work."
            }
        }
    }

    private func reload() async {
        do {
            works = try await store.listWorks().sorted { $0.updatedAt > $1.updatedAt }
            loadError = nil
        } catch {
            loadError = "Couldn't read the drafts on this device."
        }
        do {
            ideas = try await inbox.list()
            ideasLoadError = nil
        } catch {
            ideasLoadError = "Couldn't read the Ideas inbox."
        }
        hasLoaded = true
    }
}
