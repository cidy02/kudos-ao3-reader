import SwiftUI

/// Works written on this device in the Rich Text beta, with no AO3 account needed (T-576, `WritingDocumentStore`).
/// Reached from Account → Drafts on This Device while the Rich Text flag is on. A work opens in
/// `LocalChapterEditorScreen`; New Draft starts one.
struct LocalDraftsView: View {
    let store: WritingDocumentStore

    @State private var works: [WritingWork] = []
    @State private var loadError: String?
    @State private var hasLoaded = false

    init(store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot)) {
        self.store = store
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
    }

    static func detail(for work: WritingWork) -> String {
        let chapters = work.chapterOrder.count
        let count = chapters == 1 ? "1 chapter" : "\(chapters) chapters"
        return "\(count) · edited \(work.updatedAt.formatted(.relative(presentation: .named)))"
    }

    private func reload() async {
        do {
            works = try await store.listWorks().sorted { $0.updatedAt > $1.updatedAt }
            loadError = nil
        } catch {
            loadError = "Couldn't read the drafts on this device."
        }
        hasLoaded = true
    }
}
