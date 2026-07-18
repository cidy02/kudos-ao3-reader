import Foundation
import Testing
@testable import Kudos

/// Work Details' Discussion entries carry explicit initial intents into the
/// existing comments implementation: "Chapter Comments" opens By Chapter on the
/// first chapter, and "Write a Comment" opens the composer once the first page
/// has loaded. These lock in the intent handling at the CommentsModel level.
@Suite(.serialized)
@MainActor
struct CommentsInitialIntentTests {
    private static let workContext = AO3CommentsWorkContext(
        title: "Intent Work", authors: ["Creator"]
    )

    private static func makeAuth() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
    }

    private static func makeModel(
        focusesChapter: Bool = false, composes: Bool = false,
        chapters: [AO3ChapterRef] = []
    ) -> CommentsModel {
        CommentsModel(
            workID: 95_001,
            workContext: workContext,
            initialFocusesChapter: focusesChapter,
            initialComposes: composes,
            pageLoader: { _, _, _, _ in
                AO3CommentsPage(comments: [AO3Comment(id: 1, author: "Reader", isGuest: false)])
            },
            chapterLoader: { _, _ in chapters },
            pageCache: CommentsPageCache()
        )
    }

    @Test func chapterIntentOpensByChapterOnTheFirstChapter() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        let chapters = [
            AO3ChapterRef(id: 11, position: 1, title: "One"),
            AO3ChapterRef(id: 12, position: 2, title: "Two")
        ]
        let model = Self.makeModel(focusesChapter: true, chapters: chapters)

        await model.loadInitial(auth: auth)

        #expect(model.scope == .byChapter)
        #expect(model.selectedChapter?.id == 11)
        #expect(model.phase == .loaded)
    }

    @Test func chapterIntentFallsBackToAllWhenTheIndexIsEmpty() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        let model = Self.makeModel(focusesChapter: true, chapters: [])

        await model.loadInitial(auth: auth)

        #expect(model.scope == .all)
        #expect(model.selectedChapter == nil)
        #expect(model.phase == .loaded)
    }

    @Test func composeIntentOpensTheComposerForASignedInSession() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        let model = Self.makeModel(composes: true)

        await model.loadInitial(auth: auth)

        #expect(model.phase == .loaded)
        #expect(model.composerContext != nil)
        // The intent is one-shot: a later manual reload must not re-open it.
        model.closeComposer()
        await model.load(auth: auth, forceRefresh: true)
        #expect(model.composerContext == nil)
    }

    @Test func composeIntentIsInertWhenSignedOut() async {
        let auth = Self.makeAuth()
        let model = Self.makeModel(composes: true)

        await model.loadInitial(auth: auth)

        #expect(model.phase == .loaded)
        #expect(model.composerContext == nil)
    }
}
