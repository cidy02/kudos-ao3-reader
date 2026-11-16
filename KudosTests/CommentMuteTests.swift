import Foundation
import Testing
@testable import Kudos

@Suite(.serialized)
@MainActor
struct CommentMuteTests {
    private static func makeComment(
        id: Int = 42,
        author: String = "Commenter",
        isGuest: Bool = false,
        isAnonymousCreator: Bool = false,
        userPath: String? = "/users/CommenterAccount/pseuds/Commenter",
        editPath: String? = nil,
        deletePath: String? = nil,
        isDeleted: Bool = false,
        isThreadCutoff: Bool = false
    ) -> AO3Comment {
        AO3Comment(
            id: id,
            author: author,
            isGuest: isGuest,
            isAnonymousCreator: isAnonymousCreator,
            userPath: userPath,
            editPath: editPath,
            deletePath: deletePath,
            isDeleted: isDeleted,
            isThreadCutoff: isThreadCutoff
        )
    }

    @Test func muteItemIsAbsentWhenSignedOut() {
        let comment = Self.makeComment()
        #expect(comment.muteTargetRoute(isLoggedIn: false, currentUsername: nil) == nil)
        #expect(comment.muteTargetRoute(isLoggedIn: false, currentUsername: "Reader") == nil)
        #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: nil) == nil)
        #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: "  ") == nil)
    }

    @Test func muteItemIsAbsentForAnonymousAndGuestCommenters() {
        let guest = Self.makeComment(
            author: "Guest",
            isGuest: true,
            userPath: nil
        )
        let guestWithPath = Self.makeComment(
            author: "Guest",
            isGuest: true,
            userPath: "/users/Someone"
        )
        let anonCreator = Self.makeComment(
            author: "Anonymous Creator",
            isGuest: false,
            isAnonymousCreator: true,
            userPath: nil
        )
        let anonWithPath = Self.makeComment(
            author: "Anonymous Creator",
            isGuest: false,
            isAnonymousCreator: true,
            userPath: "/users/SecretCreator"
        )
        let unlinked = Self.makeComment(author: "Anonymous", isGuest: false, userPath: nil)
        let orphan = Self.makeComment(
            author: "orphan_account",
            isGuest: false,
            userPath: "/users/orphan_account"
        )

        for comment in [guest, guestWithPath, anonCreator, anonWithPath, unlinked, orphan] {
            #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: "Reader") == nil)
        }
    }

    @Test func muteItemIsAbsentForOwnAndTombstoneComments() {
        let ownByUsername = Self.makeComment(
            author: "MyOtherPseud",
            userPath: "/users/reader/pseuds/MyOtherPseud"
        )
        let ownByAction = Self.makeComment(
            author: "AnotherName",
            userPath: "/users/AnotherName",
            editPath: "/comments/42/edit"
        )
        let ownByDelete = Self.makeComment(
            author: "AnotherName",
            userPath: "/users/AnotherName",
            deletePath: "/comments/42"
        )
        let deleted = Self.makeComment(isDeleted: true)
        let cutoff = Self.makeComment(isThreadCutoff: true)

        for comment in [ownByUsername, ownByAction, ownByDelete, deleted, cutoff] {
            #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: "Reader") == nil)
        }
    }

    @Test func muteItemTargetsRegisteredCommenterWhenSignedIn() throws {
        let comment = Self.makeComment(
            author: "Avery Writes",
            userPath: "/users/Avery_Archive/pseuds/Avery%20Writes"
        )
        let route = try #require(
            comment.muteTargetRoute(isLoggedIn: true, currentUsername: "Reader")
        )
        #expect(route.username == "Avery_Archive")
        #expect(route.pseud == "Avery Writes")

        let confirmURL = route.confirmMuteURL(by: "Reader")
        #expect(confirmURL.path == "/users/Reader/muted/users/confirm_mute")
        let components = try #require(URLComponents(url: confirmURL, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.contains(URLQueryItem(name: "muted_id", value: "Avery_Archive")) == true)
    }

    @Test func moderationFlowWithoutHeaderReloadStagesConfirmFormAndFailsCleanly() async throws {
        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        await auth.login(username: "Reader", password: "pw")

        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        var loadedURLs: [URL] = []
        let model = AO3AuthorProfileModel(
            route: route,
            reloadsHeaderAfterModeration: false
        ) { url, _, _ in
            loadedURLs.append(url)
            throw AO3WriteError.rejected("You have already muted this user.")
        }

        let action = AO3AuthorWebAction(
            label: "Mute",
            url: route.confirmMuteURL(by: "Reader"),
            kind: .mute
        )
        await model.beginModeration(action: action, auth: auth)

        #expect(loadedURLs == [route.confirmMuteURL(by: "Reader")])
        #expect(model.pendingModerationForm == nil)
        #expect(model.actionMessage == "You have already muted this user.")
    }
}
