import SwiftUI

/// The existing authenticated drafts endpoint, with native form destinations.
struct WritingDraftsView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @State private var result: AO3SearchPage?
    /// Each draft's deletion date from its blurb, keyed by work id (1x).
    @State private var deletionDates: [Int: DateComponents] = [:]
    @State private var page = 1
    @State private var reload = 0
    @State private var isLoading = false
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    /// Artboard **1x**: header block, an orange notice that drafts expire, then
    /// each draft as a card with its "N days left" chip and "Created …" date.
    /// Both come from the deletion date AO3 prints on every draft's blurb
    /// (`AO3Client.parseDraftDeletionDates`, `DraftExpiry`); a draft whose notice
    /// did not parse shows neither, rather than a countdown from any other date.
    /// What is not built, and why:
    ///
    /// - **1x's Post and Delete swipe actions.** Both are AO3 writes — posting
    ///   notifies subscribers and cannot be undone — and both already live in
    ///   the editor (`WorkEditView`) behind its own buttons. A swipe is the
    ///   easiest gesture in the app to fire by accident.
    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: "Drafts",
                    subtitle: draftsTally,
                    palette: theme.scopePalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }

            Section {
                deletionNotice.pageBodyRow(top: 18, gutter: gutter)
            }

            Section {
                SubjectFormRow(label: "New work", value: "", showsDisclosure: true)
                    .subjectRowNavigation(accessibilityLabel: "New work") {
                        WritingWorkDestination(workID: nil)
                    }
                    .subjectPanel()
                    .pageBodyRow(top: 12, gutter: gutter)
            }

            if isLoading {
                ProgressView("Loading drafts…")
                    .frame(maxWidth: .infinity)
                    .pageBodyRow(top: 18, gutter: gutter)
            }
            if let errorMessage {
                Section {
                    footnote(errorMessage)
                    Button("Retry") { reload += 1 }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.scopePalette.accent)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .pageBodyRow(top: 8, gutter: gutter)
                }
            }
            if let result, loadedGeneration == auth.sessionGeneration {
                if result.works.isEmpty {
                    // The header already says "0 drafts"; this says where
                    // they come from rather than repeating it in a big glyph.
                    // "Works", not "drafts": a chapter saved as a draft on a
                    // posted work never appears here — AO3's drafts page lists
                    // `unposted_works` only.
                    footnote("Works you save as drafts appear here.")
                } else {
                    Section {
                        SubjectFieldLabel(text: "On AO3", style: .formGroup)
                            .pageBodyRow(top: 18, gutter: gutter)
                    }
                    // A background link, not a labelled `NavigationLink`: `List`
                    // puts its own chevron on a labelled one, which no other work
                    // card in the app carries. One card per row, so one link per
                    // row — the rows cannot misfire.
                    ForEach(result.works) { work in
                        DraftCard(work: work, deletion: deletionDates[work.id])
                            .subjectRowNavigation(accessibilityLabel: work.title.isEmpty ? "Untitled" : work.title) {
                                WritingWorkDestination(workID: work.id)
                            }
                            .cardRow(tintHue: CoverArt.workHue(fandoms: work.fandoms, title: work.title))
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

    /// 1x's orange notice. Artboard 1x warns that drafts expire, which is the
    /// one thing about this screen that can cost someone their writing. Its own
    /// figure is 29 days; otwarchive's `work_drafts.feature` purges a draft
    /// created 31 days ago and keeps one created 29 days ago, so the number is
    /// 30 and the spec is off by one. Stated as AO3's rule rather than the
    /// app's, because it is AO3 that deletes them. The recovery copies are
    /// `WritingTextRecovery`'s, which AO3 never sees.
    private var deletionNotice: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Text("AO3 deletes an unposted draft 30 days after it is created. The "
            + "editor's recovery copies are separate and stay on this device.")
            .font(.system(size: 12.5))
            .foregroundStyle(.primary.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(shape.fill(Color.orange.opacity(0.1)))
            .overlay(shape.strokeBorder(Color.orange.opacity(0.34), lineWidth: 0.5))
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 12, gutter: gutter)
    }

    /// 1x heads the page "N drafts · N expiring this week". The expiring count
    /// is of the drafts on this page whose deletion date parsed; with several
    /// pages it says so, since the others were not loaded.
    private var draftsTally: String? {
        guard let result, loadedGeneration == auth.sessionGeneration else { return nil }
        let count = result.works.count
        let expiring = DraftExpiry.expiringThisWeek(
            result.works.compactMap { deletionDates[$0.id] }, now: Date(), calendar: .current
        )
        if result.totalPages > 1 {
            let pageLine = "page \(result.currentPage) of \(result.totalPages)"
            return expiring > 0 ? "\(pageLine) · \(expiring) expiring this week on this page" : pageLine
        }
        let drafts = count == 1 ? "1 draft" : "\(count) drafts"
        return expiring > 0 ? "\(drafts) · \(expiring) expiring this week" : drafts
    }

    private func load() async {
        let generation = auth.sessionGeneration
        let requestedPage = page
        result = nil
        deletionDates = [:]
        errorMessage = nil
        isLoading = true
        do {
            let loaded = try await auth.loadDrafts(page: requestedPage)
            guard !Task.isCancelled, generation == auth.sessionGeneration, requestedPage == page else { return }
            loadedGeneration = generation
            deletionDates = loaded.deletionDates
            result = loaded.page
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// One draft as 1x draws it: fandom kicker, title, the AO3 required-tags
/// square, summary, and the counts AO3's blurb carries. Built from the same
/// parts as `AO3WorkRow`'s ledger card rather than that card itself: `AO3WorkRow`
/// makes its fandom a link into search and hangs a long-press menu of AO3
/// actions on the card, and neither belongs on a work nobody else can see yet.
private struct DraftCard: View {
    let work: AO3WorkSummary
    /// The deletion date AO3 printed on this draft, when it parsed.
    var deletion: DateComponents?

    @Environment(ThemeManager.self) private var themeManager

    private var fandoms: [String] {
        work.fandoms.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: work.fandoms, title: work.title))
    }

    /// The word count only. 1x also prints "1 chapter", but for a draft AO3's
    /// blurb always says 1 before the slash — otwarchive's
    /// `chapter_total_display` uses `work.posted? ? number_of_posted_chapters
    /// : 1` — while the word count sums every chapter the draft has, so a
    /// three-chapter draft would read "1 chapter · 9,000 words". Left out
    /// rather than printed wrong.
    private var counts: String? {
        guard let words = work.words else { return nil }
        return "\(words.formatted()) word\(words == 1 ? "" : "s")"
    }

    private var daysLeft: Int? {
        deletion.flatMap { DraftExpiry.daysLeft(until: $0, now: Date(), calendar: .current) }
    }

    private var created: Date? {
        deletion.flatMap { DraftExpiry.createdDate(fromDeletion: $0, calendar: .current) }
    }

    /// 1x's three tones: red with three days or fewer, orange within the week,
    /// mint beyond it.
    private func expiryColor(_ daysLeft: Int) -> Color {
        switch daysLeft {
        case ...3: .red
        case ...7: .orange
        default: .mint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 13) {
                VStack(alignment: .leading, spacing: 5) {
                    if fandoms.first != nil || daysLeft != nil {
                        HStack(alignment: .top, spacing: 6) {
                            if let first = fandoms.first {
                                SubjectKicker(text: first, palette: palette, trailingCount: fandoms.count - 1)
                            }
                            if let daysLeft {
                                SubjectStateBadge(
                                    title: DraftExpiry.chipText(daysLeft: daysLeft),
                                    color: expiryColor(daysLeft)
                                )
                                .fixedSize()
                            }
                        }
                    }
                    Text(work.title.isEmpty ? "Untitled" : work.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                WorkStatusIconGrid(
                    rating: work.rating.isEmpty ? nil : work.rating,
                    categories: work.categories,
                    warnings: work.warnings,
                    completion: WorkCompletionStatus(isComplete: work.isComplete),
                    tileSize: 22,
                    announcesToVoiceOver: true,
                    showsTray: true
                )
            }
            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if counts != nil || created != nil {
                HStack(spacing: 8) {
                    if let counts {
                        Text(counts)
                    }
                    Spacer(minLength: 8)
                    if let created {
                        Text("Created \(created.formatted(.dateTime.day().month(.abbreviated).year()))")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
