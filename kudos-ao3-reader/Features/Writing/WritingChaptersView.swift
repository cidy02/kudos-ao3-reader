import SwiftUI

/// 1bo's Chapters row: the work's chapters, each opening its edit form.
///
/// The list is AO3's own chapter index (`/works/<id>/navigate`), read by the
/// parser Comments already uses (`AO3Client.chapterIndex`). Signed in as the
/// owner it includes draft chapters — otwarchive's `works#navigate` passes
/// `include_drafts: … user_is_owner_or_invited?` — so every chapter is
/// reachable. It carries no word counts (`chapters_in_order` selects no
/// `word_count`), so a row shows AO3's date instead.
struct WritingChaptersView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    let workID: Int
    let workTitle: String
    var onSaved: () -> Void = {}
    @State private var chapters: [AO3ChapterRef]?
    @State private var loadedGeneration: Int?
    @State private var loadedReload: Int?
    @State private var errorMessage: String?
    @State private var reload = 0

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account", title: "Chapters",
                    subtitle: Self.subtitle(workTitle: workTitle, count: chapters?.count),
                    palette: theme.scopePalette, gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }
            if let chapters, loadedGeneration == auth.sessionGeneration {
                Section { rows(chapters) }
            } else if let errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Retry") { reload += 1 }
                }
                .pageBodyRow(top: 18, gutter: gutter)
            } else {
                ProgressView("Loading chapters…")
                    .frame(maxWidth: .infinity)
                    .pageBodyRow(top: 18, gutter: gutter)
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        #if os(macOS)
        .navigationTitle("Chapters")
        #endif
        .subjectScreenWash(palette: theme.scopePalette)
        .task(id: "\(auth.sessionGeneration):\(reload)") { await load() }
    }

    @ViewBuilder
    private func rows(_ chapters: [AO3ChapterRef]) -> some View {
        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
            SubjectFormRow(label: chapter.displayName, value: chapter.dateText, showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: chapter.displayName) {
                    WritingChapterDestination(
                        workID: workID, workTitle: workTitle,
                        chapterID: chapter.id, chapterCount: chapters.count
                    ) {
                        reload += 1
                        onSaved()
                    }
                }
                .panelSegment(index, of: chapters.count, gutter: gutter)
        }
    }

    /// Kept across reappearance, like the other writing loaders. Rows stay up
    /// while a same-session reload runs: a row's link is what keeps its pushed
    /// chapter form open, so clearing the list would pop it.
    private func load() async {
        let generation = auth.sessionGeneration
        if loadedGeneration == generation, loadedReload == reload { return }
        if loadedGeneration != generation { chapters = nil }
        errorMessage = nil
        do {
            let request = try auth.authenticatedRequest(for: AO3Client.chapterIndexURL(workID: workID))
            let loaded = try await AO3Client.shared.chapterIndex(workID: workID, request: request)
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            chapters = loaded
            loadedGeneration = generation
            loadedReload = reload
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            if chapters == nil { errorMessage = UserFacingError.message(for: error) }
        }
    }

    static func subtitle(workTitle: String, count: Int?) -> String {
        guard let count else { return workTitle }
        return "\(workTitle) · \(count) \(count == 1 ? "chapter" : "chapters")"
    }
}
