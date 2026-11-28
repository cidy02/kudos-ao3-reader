import SwiftUI

/// Navigation value for a whole collection. Deliberately not
/// `AO3AccountWorksList.Kind.collection`, which still means "the works page of a
/// collection" and is pushed from other places — this one opens all three segments.
struct AO3CollectionDestination: Hashable {
    let slug: String
    let title: String
}

/// Artboard **1ci** — a collection as someone browsing it sees it.
///
/// The other side of 1cd. Its three segments are three different AO3 pages, which
/// is why they load independently rather than as one payload — the spec's own note
/// says so, and it is also what stops opening the screen costing three requests
/// when a reader only ever looks at Works.
///
/// **Anonymous is the collection's state, not the work's.** The same work reads as
/// Anonymous here and under its creator everywhere else, which is why the badge sits
/// on the card rather than replacing the byline: a reader who sees "Anonymous" with
/// no explanation learns nothing, and one who sees a badge learns that this
/// collection is hiding creators.
struct AO3CollectionDetailView: View {
    @AppStorage("hideMatureContent") private var hideMature = true
    let slug: String
    let title: String

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @ScaledMetric(relativeTo: .headline) private var stateTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var actionSize: CGFloat = 13

    @State private var show: AO3CollectionShow?
    @State private var segment: Segment = .works
    @State private var works: [AO3WorkSummary] = []
    @State private var bookmarks: [AO3WorkSummary] = []
    @State private var people: [AO3CollectionPerson] = []
    @State private var currentPages: [Segment: Int] = [:]
    @State private var totalPages: [Segment: Int] = [:]
    /// Which segments have already been fetched, so switching back to one does not
    /// re-request it. Keyed by segment rather than a set of booleans so a fifth
    /// segment cannot be added without deciding this.
    @State private var loaded: Set<Segment> = []
    @State private var phase: Phase = .idle
    @State private var expandAll = false
    @State private var showingPrompts = false
    @State private var loadGeneration = 0
    @State private var loadedSessionGeneration: Int?
    @State private var pageLoadTask: Task<Void, Never>?

    private enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    private struct LoadID: Equatable {
        var segment: Segment
        var sessionGeneration: Int
        var isLoggedIn: Bool
    }

    nonisolated enum Segment: String, CaseIterable, Hashable, Sendable {
        case works
        case bookmarks
        case people
        case profile

        var title: String {
            switch self {
            case .works: "Works"
            case .bookmarks: "Bookmarks"
            case .people: "Participants"
            case .profile: "Profile"
            }
        }
    }

    var body: some View {
        List {
            Section {
                contextCard.pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                if let show, !boardStatCells(for: show).isEmpty {
                    ChallengeBoardStatStrip(cells: boardStatCells(for: show), surface: .list)
                        .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
                chipRail.pageBodyRow(top: 14, gutter: 0)
            }

            let manage = manageRows
            if !manage.isEmpty {
                Section {
                    ChallengeBoardListSectionHeader(title: "Manage")
                        .padding(.bottom, 6)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.accountGutter)
                }
                // One `List` row per screen, as segments of one card. The card
                // was one `VStack` row, and a `List` row fires every
                // `NavigationLink` inside it — tapping Moderation pushed every
                // manage screen at once.
                Section {
                    ForEach(Array(manage.enumerated()), id: \.offset) { index, row in
                        row.panelSegment(index, of: manage.count, gutter: SubjectMetrics.accountGutter)
                    }
                }
            }

            switch phase {
            case .loading where segmentRowsAreEmpty:
                Section { loadingRow.pageBodyRow(top: 20, gutter: SubjectMetrics.accountGutter) }
            case let .failed(message):
                Section { failureCard(message).pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter) }
            default:
                segmentContent
                if segment != .profile, totalPage(for: segment) > 1 {
                    Section {
                        paginationBar(for: segment)
                            .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                    }
                }
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: show?.collection.title ?? title, palette: palette, role: .content)
        .navigationDestination(isPresented: $showingPrompts) {
            PromptMemeView(
                collectionSlug: slug,
                collectionTitle: show?.collection.title ?? title,
                viewerIsOwner: show?.collection.viewerIsOwner ?? false,
                challengeKind: show?.collection.challengeKind
            )
        }
        #if DEBUG
        // A shot's manage screen opens from the page, not from its row: at the largest
        // text the row is below the fold, and a `List` never builds a row it hasn't shown.
        .navigationDestination(isPresented: .constant(debugManageEntry != nil)) {
            debugManageEntry?.destination()
        }
        #endif
        .toolbar {
            ActionToolbar(items: [AnyView(
                WorkListMoreMenu {
                    if let url = show?.collection.url ?? AO3CollectionURL.show(slug: slug) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            router.open(url)
                        } label: {
                            Label("Open on AO3", systemImage: "safari")
                        }
                    }
                    if hideMature {
                        MatureRevealToggle()
                    }
                }
            )])
        }
        .task(id: LoadID(
            segment: segment,
            sessionGeneration: auth.sessionGeneration,
            isLoggedIn: auth.isLoggedIn
        )) {
            pageLoadTask?.cancel()
            loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
            if loadedSessionGeneration != auth.sessionGeneration {
                clearLoadedSession()
                loadedSessionGeneration = auth.sessionGeneration
            }
            if loaded.contains(segment) {
                phase = .loaded
            } else {
                await loadIfNeeded()
            }
        }
        .refreshable {
            loaded.remove(segment)
            await loadIfNeeded()
        }
        .onDisappear {
            pageLoadTask?.cancel()
            loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ao3CollectionDeleted)) { notification in
            guard notification.deletesCollection(slug: slug) else { return }
            pageLoadTask?.cancel()
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ao3CollectionChanged)) { notification in
            guard notification.object as? String == slug else { return }
            // Every segment: what the reader may do here changed, not only the one showing.
            loaded.removeAll()
            Task { await loadIfNeeded() }
        }
            .screenTint(palette)
    }

    // MARK: Header

    private var contextSymbol: String {
        switch show?.collection.challengeKind {
        case .giftExchange: "gift"
        case .promptMeme: "bubble.left"
        case nil: "archivebox"
        }
    }

    private var contextCard: some View {
        let collection = show?.collection
        return ChallengeBoardContextCard(
            systemImage: contextSymbol,
            kicker: collection.map { ChallengesBoardCopy.collectionPageKicker(for: $0) } ?? "Collection",
            title: collection?.title ?? title,
            meta: collection.map { ChallengesBoardCopy.collectionPageMeta(for: $0) },
            palette: palette,
            surface: .list
        )
    }

    /// Works / Bookmarks. Each cell is dropped when AO3 gave no exact figure,
    /// rather than substituting the number of rows loaded from one page.
    private func boardStatCells(for show: AO3CollectionShow) -> [ChallengeBoardStatStrip.Cell] {
        var cells: [ChallengeBoardStatStrip.Cell] = []
        if let works = show.collection.worksCount {
            cells.append(ChallengeBoardStatStrip.Cell(value: works.formatted(), label: "Works"))
        }
        if let bookmarks = show.collection.bookmarksCount {
            cells.append(ChallengeBoardStatStrip.Cell(value: bookmarks.formatted(), label: "Bookmarks"))
        }
        return cells
    }

    private var chipRail: some View {
        AccessibilityChipRail(horizontalPadding: SubjectMetrics.accountGutter) {
            chipButton(for: .works)
            chipButton(for: .bookmarks)
            if show?.dashboard.promptsURL != nil {
                Button {
                    showingPrompts = true
                } label: {
                    ChallengeBoardChipLabel(text: "Prompts", isSelected: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Prompts")
            }
            chipButton(for: .people)
            chipButton(for: .profile)
        }
    }

    private func chipButton(for option: Segment) -> some View {
        let selected = segment == option
        return Button {
            segment = option
        } label: {
            ChallengeBoardChipLabel(text: option.title, isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: show?.collection.title ?? title)
        )
    }

    // MARK: Segments

    @ViewBuilder
    private var segmentContent: some View {
        switch segment {
        case .works:
            workRows(works, segment: .works, emptyMessage: ChallengesBoardCopy.collectionPageEmptyWorks)
        case .bookmarks:
            workRows(
                bookmarks,
                segment: .bookmarks,
                emptyMessage: ChallengesBoardCopy.collectionPageEmptyBookmarks
            )
        case .people: peopleRows
        case .profile: profileRows
        }
    }

    @ViewBuilder
    private func workRows(
        _ rows: [AO3WorkSummary], segment: Segment, emptyMessage: String
    ) -> some View {
        if rows.isEmpty {
            Section {
                emptyCard(emptyMessage).pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        } else {
            Section {
                ChallengeBoardListSectionHeader(title: "Recent", count: exactTotal(for: segment))
                    .pageBodyRow(top: 18, gutter: SubjectMetrics.accountGutter)
                ForEach(rows) { work in
                    EnrichingAO3WorkRow(
                        work: work, expandAll: expandAll, presentation: .searchLedger
                    )
                    .overlay(alignment: .topTrailing) {
                        collectionStateBadge(for: work).padding(10)
                    }
                    .cardRow(chrome: .plain)
                }
            }
        }
    }

    /// The spec's card badge. Only Anonymous is derivable from the works page — AO3
    /// prints the byline as "Anonymous" and gives nothing else away.
    @ViewBuilder
    private func collectionStateBadge(for work: AO3WorkSummary) -> some View {
        if isAnonymous(work) {
            ChallengeBoardBadge(text: "Anonymous", style: .neutral)
                .accessibilityLabel("Anonymous in this collection")
        }
    }

    /// AO3 renders an anonymous work's byline as the literal word. Matched
    /// case-insensitively against the whole byline rather than by substring, so a
    /// creator actually called "anonymously_yours" is not badged.
    private func isAnonymous(_ work: AO3WorkSummary) -> Bool {
        let byline = work.authors
            .joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return byline.compare("Anonymous", options: .caseInsensitive) == .orderedSame
    }

    @ViewBuilder
    private var peopleRows: some View {
        if people.isEmpty {
            Section {
                emptyCard(ChallengesBoardCopy.collectionPageEmptyParticipants)
                    .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        } else {
            Section {
                ChallengeBoardListSectionHeader(
                    title: ChallengesBoardCopy.collectionPageParticipantsTitle,
                    countText: Self.peopleCountLabel(
                        count: people.count,
                        currentPage: currentPage(for: .people),
                        totalPages: totalPage(for: .people)
                    )
                )
                .pageBodyRow(top: 18, gutter: SubjectMetrics.accountGutter)
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    VStack(spacing: 0) {
                        if index > 0 { SubjectRowSeparator(inset: 48) }
                        AO3CollectionPersonRow(person: person, palette: palette)
                    }
                    .pageBodyRow(top: 0, gutter: SubjectMetrics.accountGutter)
                }
            }
        }
    }

    @ViewBuilder
    private var profileRows: some View {
        let blocks: [(title: String, body: String)] = [
            ("Introduction", show?.introduction ?? ""),
            ("FAQ", show?.faq ?? ""),
            ("Rules", show?.rules ?? "")
        ].filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if blocks.isEmpty {
            Section {
                emptyCard(ChallengesBoardCopy.collectionPageEmptyProfile)
                    .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        } else {
            ForEach(blocks, id: \.title) { block in
                Section {
                    ChallengeBoardListSectionHeader(title: block.title)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.accountGutter)
                    Text(block.body)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .subjectPanel()
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }
            }
        }
    }

    // MARK: Chrome

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView().accentFill()
            Spacer()
        }
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: bodySize))
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't load this collection")
                .font(.system(size: stateTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: bodySize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                loaded.remove(segment)
                startPageLoad(segment: segment, page: currentPage(for: segment))
            }
            .buttonStyle(.borderless)
            .font(.system(size: actionSize, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    // MARK: Loading

    /// Loads the collection header once, then only the segment being shown.
    ///
    /// Every request goes through the signed-in session when there is one and
    /// anonymously otherwise — a collection is public, and requiring a login to
    /// look at one would be a regression against the website.
    private func loadIfNeeded() async {
        let requestedSegment = segment
        guard !loaded.contains(requestedSegment) else { return }
        await load(segment: requestedSegment, page: currentPage(for: requestedSegment))
    }

    private func load(segment requestedSegment: Segment, page: Int) async {
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        let generation = loadGeneration
        let expectedSessionGeneration = auth.sessionGeneration
        phase = .loading
        // Built from the collection's own URL when there is a session; the fetches
        // below each retarget it (`request.url = …`), which is the established
        // pattern in AO3Client+Collections. Nil when signed out, which is a normal
        // state here rather than a failure.
        let request: URLRequest? = {
            guard auth.isLoggedIn, let url = AO3CollectionURL.show(slug: slug) else { return nil }
            return try? auth.authenticatedRequest(for: url)
        }()
        do {
            // Kept as soon as it passes the fence, so a failed segment page does
            // not hide the header and Manage rows or refetch the show on retry.
            if show == nil {
                let fetched = try await AO3Client.shared.collectionShow(slug: slug, request: request)
                guard shouldApplyLoad(
                    generation: generation,
                    expectedSessionGeneration: expectedSessionGeneration,
                    requestedSegment: requestedSegment
                ) else { return }
                show = fetched
            }
            switch requestedSegment {
            case .works:
                let result = try await AO3Client.shared.collectionWorks(
                    slug: slug, page: page, request: request
                )
                guard shouldApplyLoad(
                    generation: generation,
                    expectedSessionGeneration: expectedSessionGeneration,
                    requestedSegment: requestedSegment
                ) else { return }
                works = result.works
                currentPages[.works] = result.currentPage
                totalPages[.works] = result.totalPages
            case .bookmarks:
                let result = try await AO3Client.shared.collectionBookmarks(
                    slug: slug, page: page, request: request
                )
                guard shouldApplyLoad(
                    generation: generation,
                    expectedSessionGeneration: expectedSessionGeneration,
                    requestedSegment: requestedSegment
                ) else { return }
                bookmarks = result.works
                currentPages[.bookmarks] = result.currentPage
                totalPages[.bookmarks] = result.totalPages
            case .people:
                let result = try await AO3Client.shared.collectionPeople(
                    slug: slug, page: page, request: request
                )
                guard shouldApplyLoad(
                    generation: generation,
                    expectedSessionGeneration: expectedSessionGeneration,
                    requestedSegment: requestedSegment
                ) else { return }
                people = result.people
                currentPages[.people] = result.currentPage
                totalPages[.people] = result.totalPages
            case .profile:
                break
            }
            loaded.insert(requestedSegment)
            phase = .loaded
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch let error as AO3Error {
            guard shouldApplyLoad(
                generation: generation,
                expectedSessionGeneration: expectedSessionGeneration,
                requestedSegment: requestedSegment
            ) else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard shouldApplyLoad(
                generation: generation,
                expectedSessionGeneration: expectedSessionGeneration,
                requestedSegment: requestedSegment
            ) else { return }
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    private func startPageLoad(segment: Segment, page: Int) {
        pageLoadTask?.cancel()
        pageLoadTask = Task { await load(segment: segment, page: page) }
    }

    private func shouldApplyLoad(
        generation: Int, expectedSessionGeneration: Int, requestedSegment: Segment
    ) -> Bool {
        !Task.isCancelled && requestedSegment == segment
            && AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: generation,
                loadGeneration: loadGeneration,
                capturedSessionGeneration: expectedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            )
    }

    private func clearLoadedSession() {
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        show = nil
        works = []
        bookmarks = []
        people = []
        currentPages = [:]
        totalPages = [:]
        loaded = []
        phase = .idle
    }
}

// Paging helpers. Out of the struct body only for its length.
extension AO3CollectionDetailView {
    /// This page's row count is never presented as the collection's total.
    nonisolated static func peopleCountLabel(
        count: Int, currentPage: Int, totalPages: Int
    ) -> String {
        "\(count) on this page · page \(currentPage) of \(totalPages)"
    }

    private func exactTotal(for segment: Segment) -> Int? {
        switch segment {
        case .works: show?.collection.worksCount
        case .bookmarks: show?.collection.bookmarksCount
        case .people, .profile: nil
        }
    }

    private func currentPage(for segment: Segment) -> Int {
        currentPages[segment] ?? 1
    }

    private func totalPage(for segment: Segment) -> Int {
        totalPages[segment] ?? 1
    }

    private var segmentRowsAreEmpty: Bool {
        switch segment {
        case .works: works.isEmpty
        case .bookmarks: bookmarks.isEmpty
        case .people: people.isEmpty
        case .profile: show == nil
        }
    }

    private func paginationBar(for segment: Segment) -> some View {
        SearchPaginationBar(
            currentPage: currentPage(for: segment),
            totalPages: totalPage(for: segment),
            isLoading: phase == .loading,
            palette: palette
        ) { page in
            startPageLoad(segment: segment, page: page)
        }
    }
}

/// One member of a collection matching `ListScreen.dc.html` rows (36×36 circular avatar,
/// 17 pt semibold name, 13 pt secondary work count).
struct AO3CollectionPersonRow: View {
    let person: AO3CollectionPerson
    let palette: SubjectPalette

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var countSize: CGFloat = 13

    var body: some View {
        let personColor = theme.appTheme.subjectPalette(hue: CoverArt.hue(for: person.identity.displayName)).accent
        let worksText = ChallengesBoardCopy.collectionPersonWorksText(person.workCount)
        HStack(spacing: 12) {
            ChallengeBoardAvatar(
                text: ChallengesBoardCopy.personInitial(for: person.identity.displayName),
                color: personColor,
                shapeKind: .circle(size: 36)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(person.identity.displayName)
                    .font(.system(size: nameSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let worksText {
                    Text(worksText)
                        .font(.system(size: countSize))
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Manage

extension AO3CollectionDetailView {
    /// Every native screen this collection currently offers, gated exactly on
    /// what `show` says AO3 offered — never rendered as a disabled row. Built as
    /// an array (rather than an `@ViewBuilder` `Group`) because each segment
    /// needs to know how many rows survived gating to round the right corners
    /// and draw separators only between rows that actually show.
    ///
    /// No "Tag Set" row: `TagSetView` takes a `tagSetID`, and nothing on
    /// `AO3CollectionShow`/`AO3CollectionDashboard`/`AO3ChallengeSettings`
    /// carries one for this collection to hand it. That wiring waits until
    /// something in the model surfaces an id.
    private var manageEntries: [ManageEntry] {
        // A new session renders before the load task clears `show`; the
        // previous account's owner rows must not draw for that pass.
        guard let show, loadedSessionGeneration == auth.sessionGeneration else { return [] }
        var entries: [ManageEntry] = []

        if show.isMaintainer {
            entries.append(ManageEntry("Maintainers") {
                CollectionMaintainersView(collectionSlug: slug, collectionTitle: title)
            })
            entries.append(ManageEntry("Moderation") {
                CollectionModerationView(
                    collectionSlug: slug,
                    collectionTitle: title,
                    viewerIsOwner: show.collection.viewerIsOwner
                )
            })
        }
        if AO3CollectionOwnerControls.areVisible(viewerIsOwner: show.collection.viewerIsOwner) {
            entries.append(ManageEntry("Collection Settings") {
                AO3CollectionFormView(
                    slug: slug,
                    onDeleted: { dismiss() }
                )
            })
        }
        // 1bz is explicitly the moderator's read, so gate it on maintainer too,
        // not just signUpsURL's presence.
        if show.dashboard.signUpsURL != nil, show.isMaintainer {
            entries.append(ManageEntry("Sign-Ups") {
                ChallengeSignUpsView(
                    collectionSlug: slug, collectionTitle: title, challengeKind: show.collection.challengeKind
                )
            })
        }
        if show.dashboard.assignmentsURL != nil, show.isMaintainer {
            entries.append(ManageEntry("Assignments") {
                ChallengeAssignmentsView(
                    collectionSlug: slug,
                    collectionTitle: title,
                    viewerIsOwner: show.collection.viewerIsOwner,
                    challengeKind: show.collection.challengeKind
                )
            })
        }
        // Not maintainer-gated: any participant claims/fills prompts.
        if show.dashboard.promptsURL != nil {
            entries.append(ManageEntry("Prompts") {
                PromptMemeView(
                    collectionSlug: slug, collectionTitle: title,
                    viewerIsOwner: show.collection.viewerIsOwner,
                    challengeKind: show.collection.challengeKind
                )
            })
        }
        // A maintainer can also be a participant, so this is independent of
        // `isMaintainer` above.
        if show.dashboard.signUpsURL != nil, auth.isLoggedIn {
            entries.append(ManageEntry("Your Sign-Up") {
                ChallengeSignUpView(collectionSlug: slug, collectionTitle: title)
            })
        }
        // Owners only (REDESIGN_DECISIONS 1by): AO3 prints the Challenge Settings
        // link for collection owners alone and refuses its edit page to everyone
        // else, moderators included (otwarchive Q5), so the link is the owner
        // signal. The read (1by) pushes the edit form (1cf).
        if show.dashboard.challengeSettingsURL != nil,
           AO3CollectionOwnerControls.areVisible(viewerIsOwner: show.collection.viewerIsOwner) {
            entries.append(ManageEntry("Challenge Settings") {
                ChallengeSettingsView(
                    collectionSlug: slug,
                    collectionTitle: title,
                    viewerIsOwner: show.collection.viewerIsOwner,
                    challengeKind: show.collection.challengeKind
                )
            })
        }

        return entries
    }

    private var manageRows: [AnyView] {
        manageEntries.map { entry in AnyView(manageRow(entry.label, destination: entry.destination)) }
    }

    #if DEBUG
    /// The manage screen a shot opens (`DebugLaunchRoute.manageRow`).
    private var debugManageEntry: ManageEntry? {
        guard let label = DebugLaunchRoute.manageRow else { return nil }
        return manageEntries.first { $0.label == label }
    }
    #endif

    /// One pushable row that draws its own chevron, with the link in the
    /// background so `List` adds no second one.
    private func manageRow<Destination: View>(
        _ label: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        SubjectFormRow(label: label, showsDisclosure: true) { EmptyView() }
            .subjectRowNavigation(accessibilityLabel: label, destination: destination)
    }
}

/// One manage screen: its row's label and what the row pushes.
private struct ManageEntry {
    let label: String
    let destination: () -> AnyView

    init<Destination: View>(_ label: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.label = label
        self.destination = { AnyView(destination()) }
    }
}
