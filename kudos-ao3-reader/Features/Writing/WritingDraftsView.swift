import SwiftUI

/// The existing authenticated drafts endpoint, with native form destinations.
struct WritingDraftsView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @State private var result: AO3SearchPage?
    @State private var page = 1
    @State private var reload = 0
    @State private var isLoading = false
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?

    var body: some View {
        List {
            SubjectHeaderBlock(
                kicker: "AO3 Account",
                title: "Drafts",
                subtitle: draftsTally,
                palette: theme.scopePalette,
                gutter: SubjectMetrics.accountGutter
            )
            .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            NavigationLink("New work") { WritingWorkDestination(workID: nil) }
            Text("AO3 drafts are unpublished. Local editor recovery copies stay on this device.")
                .font(.caption).foregroundStyle(.secondary)
            // Artboard 1x warns that drafts expire, which is the one thing about
            // this screen that can cost someone their writing. Its own figure is
            // 29 days; otwarchive's `work_drafts.feature` purges a draft created
            // 31 days ago and keeps one created 29 days ago, so the number is 30
            // and the spec is off by one. Stated as AO3's rule rather than the
            // app's, because it is AO3 that deletes them.
            Text("AO3 deletes an unposted draft 30 days after it is created.")
                .font(.caption).foregroundStyle(.secondary)
            if isLoading { ProgressView("Loading drafts…") }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
                Button("Retry") { reload += 1 }
            }
            if let result, loadedGeneration == auth.sessionGeneration {
                if result.works.isEmpty {
                    ContentUnavailableView("No drafts", systemImage: "doc.badge.clock")
                }
                ForEach(result.works) { work in
                    NavigationLink { WritingWorkDestination(workID: work.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(work.title).font(.headline)
                            Text(work.fandoms.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                // 1k's switcher pill, the same control every other paged screen
                // in the redesign uses. This was a Previous / Next pair with the
                // page as static text between them.
                if result.totalPages > 1 {
                    SearchPaginationBar(
                        currentPage: result.currentPage,
                        totalPages: result.totalPages,
                        isLoading: isLoading,
                        palette: theme.scopePalette
                    ) { page = $0 }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .cardList()
        // The page states its own name in the header block above, per 1x.
        .hidesNavigationBarChrome()
        .subjectScreenWash(palette: theme.scopePalette)
        .task(id: "\(auth.sessionGeneration):\(page):\(reload)") { await load() }
        .refreshable { reload += 1 }
    }

    /// 1x heads the page "N drafts · N expiring this week". The second half is
    /// not drawn: the drafts endpoint returns work summaries with no creation
    /// date, so there is nothing to measure "expiring" against without asking AO3
    /// for each draft separately.
    private var draftsTally: String? {
        guard let result, loadedGeneration == auth.sessionGeneration else { return nil }
        let count = result.works.count
        if result.totalPages > 1 { return "page \(result.currentPage) of \(result.totalPages)" }
        return count == 1 ? "1 draft" : "\(count) drafts"
    }

    private func load() async {
        let generation = auth.sessionGeneration
        let requestedPage = page
        result = nil
        errorMessage = nil
        isLoading = true
        do {
            let loaded = try await auth.loadDrafts(page: requestedPage)
            guard !Task.isCancelled, generation == auth.sessionGeneration, requestedPage == page else { return }
            loadedGeneration = generation
            result = loaded
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct WritingWorkDestination: View {
    @Environment(AO3AuthService.self) private var auth
    let workID: Int?
    @State private var form: AO3WorkForm?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let form, loadedGeneration == auth.sessionGeneration { WorkEditView(form: form).id(auth.sessionGeneration) }
            else if let errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Retry") { retry += 1 }
                }.padding()
            } else { ProgressView("Loading work form…") }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            // `.task` re-runs every time this view reappears — including on
            // Back from any editor it pushed — and resetting `form` here threw
            // away everything typed. Measured on the simulator: a title typed
            // on the new-work form was gone after one round trip to Fandoms.
            // A form already loaded for this session is kept; Retry and a
            // session change still reload, because they change the id or clear
            // the form first.
            if form != nil, loadedGeneration == auth.sessionGeneration { return }
            form = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded: AO3WorkForm
                if let workID { loaded = try await auth.loadWorkForm(workID: workID) }
                else { loaded = try await auth.loadNewWorkForm() }
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                form = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Loads a posted work's tag form and hands it to `EditTagsView` — artboard
/// **1bp**, which keeps tags on their own page "so a tag fix never opens the
/// text".
///
/// The screen was written and then never reachable: `EditTagsView` had no caller
/// anywhere in the app or its tests. Same loader shape as its two siblings here,
/// including the `sessionGeneration` keying, so a sign-out mid-load cannot hand
/// the next account a form built for the previous one.
struct WritingTagsDestination: View {
    @Environment(AO3AuthService.self) private var auth
    let workID: Int
    /// Forwarded to `EditTagsView` — see `WorkEditView.needsTagRefresh`.
    var onSaved: () -> Void = {}
    @State private var form: AO3EditTagsForm?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let form, loadedGeneration == auth.sessionGeneration {
                EditTagsView(form: form, onSaved: onSaved).id(auth.sessionGeneration)
            } else if let errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Retry") { retry += 1 }
                }.padding()
            } else {
                ProgressView("Loading tags…")
            }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            // Kept across reappearance — see `WritingWorkDestination`.
            if form != nil, loadedGeneration == auth.sessionGeneration { return }
            form = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded = try await auth.loadEditTagsForm(workID: workID)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                form = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Loads AO3's bulk-edit form for a selection and hands it to
/// `EditMultipleWorksView` — artboard **1bn**.
///
/// `EditMultipleWorksView` and `AO3WorkActions.loadBulkEditForm(workIDs:)` were
/// both written and referenced nowhere. This is the way in.
///
/// The form is AO3's own `/users/<name>/works/edit_multiple`, so it only means
/// anything for works the signed-in account owns — the caller gates on that.
/// Same `sessionGeneration` keying as the other writing loaders.
struct WritingBulkEditDestination: View {
    @Environment(AO3AuthService.self) private var auth
    let workIDs: [Int]
    @State private var form: AO3BulkEditForm?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let form, loadedGeneration == auth.sessionGeneration {
                EditMultipleWorksView(form: form).id(auth.sessionGeneration)
            } else if let errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Retry") { retry += 1 }
                }.padding()
            } else {
                ProgressView("Loading \(workIDs.count) works…")
            }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            // Kept across reappearance — see `WritingWorkDestination`.
            if form != nil, loadedGeneration == auth.sessionGeneration { return }
            form = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded = try await auth.loadBulkEditForm(workIDs: workIDs)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                form = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct WritingChapterDestination: View {
    @Environment(AO3AuthService.self) private var auth
    let workID: Int
    let workTitle: String
    var onSaved: () -> Void = {}
    @State private var form: AO3ChapterForm?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let form, loadedGeneration == auth.sessionGeneration { AddChapterView(form: form, workTitle: workTitle, onSaved: onSaved).id(auth.sessionGeneration) }
            else if let errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Retry") { retry += 1 }
                }.padding()
            } else { ProgressView("Loading chapter form…") }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            // Kept across reappearance — see `WritingWorkDestination`.
            if form != nil, loadedGeneration == auth.sessionGeneration { return }
            form = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded = try await auth.loadChapterForm(workID: workID, chapterID: nil)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                form = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
