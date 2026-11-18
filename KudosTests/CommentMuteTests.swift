import Foundation
import SwiftUI
import Testing
@testable import Kudos

@Suite(.serialized)
@MainActor
struct CommentMuteTests {
    private final class BundleAnchor {}

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

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

    /// Walks a `CommentMenuItems` SwiftUI view tree to confirm the Mute label
    /// is actually rendered (or absent) rather than testing the model predicate alone.
    private static func renderedMenuContains(_ needle: String, in view: CommentMenuItems) -> Bool {
        var queue: [Any] = [view.body]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let text = current as? String, text.contains(needle) {
                return true
            }
            if let localized = current as? LocalizedStringKey,
               String(describing: localized).contains(needle) {
                return true
            }
            let mirror = Mirror(reflecting: current)
            if mirror.displayStyle == .optional {
                if let child = mirror.children.first { queue.append(child.value) }
                continue
            }
            queue += mirror.children.map(\.value)
        }
        return false
    }

    @Test func muteItemIsAbsentWhenSignedOut() {
        let comment = Self.makeComment(author: "Avery Writes")
        #expect(comment.muteTargetRoute(isLoggedIn: false, currentUsername: nil) == nil)
        #expect(comment.muteTargetRoute(isLoggedIn: false, currentUsername: "Reader") == nil)
        #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: nil) == nil)
        #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: "  ") == nil)

        var handlers = CommentThreadHandlers.noop
        handlers.onMute = { _ in }
        let signedOutMenu = CommentMenuItems(
            comment: comment,
            isLoggedIn: false,
            currentUsername: nil,
            showsReply: false,
            handlers: handlers
        )
        #expect(!Self.renderedMenuContains("Mute Avery Writes", in: signedOutMenu))
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

        var handlers = CommentThreadHandlers.noop
        handlers.onMute = { _ in }
        for comment in [guest, guestWithPath, anonCreator, anonWithPath, unlinked, orphan] {
            #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: "Reader") == nil)
            let menu = CommentMenuItems(
                comment: comment,
                isLoggedIn: true,
                currentUsername: "Reader",
                showsReply: true,
                handlers: handlers
            )
            #expect(!Self.renderedMenuContains("Mute \(comment.author)", in: menu))
        }
    }

    @Test func muteItemIsAbsentForOwnAndTombstoneComments() {
        let ownByUsername = Self.makeComment(
            author: "MyOtherPseud",
            userPath: "/users/reader/pseuds/MyOtherPseud"
        )
        let ownWithoutEditAfterReply = Self.makeComment(
            author: "MyOtherPseud",
            userPath: "/users/reader/pseuds/MyOtherPseud",
            editPath: nil,
            deletePath: "/comments/42"
        )
        let ownByEditAction = Self.makeComment(
            author: "AnotherName",
            userPath: "/users/AnotherName",
            editPath: "/comments/42/edit"
        )
        let deleted = Self.makeComment(isDeleted: true)
        let cutoff = Self.makeComment(isThreadCutoff: true)

        var handlers = CommentThreadHandlers.noop
        handlers.onMute = { _ in }
        for comment in [ownByUsername, ownWithoutEditAfterReply, ownByEditAction, deleted, cutoff] {
            #expect(comment.muteTargetRoute(isLoggedIn: true, currentUsername: "Reader") == nil)
            let menu = CommentMenuItems(
                comment: comment,
                isLoggedIn: true,
                currentUsername: "Reader",
                showsReply: true,
                handlers: handlers
            )
            #expect(!Self.renderedMenuContains("Mute \(comment.author)", in: menu))
        }
    }

    @Test func workOwnerCanStillMuteOtherCommenterWhenDeletePathIsPresent() throws {
        // A work's creator receives a Delete link on other readers' comments.
        let commenterOnOwnersWork = Self.makeComment(
            author: "Avery Writes",
            userPath: "/users/Avery_Archive/pseuds/Avery%20Writes",
            editPath: nil,
            deletePath: "/comments/42"
        )
        let route = try #require(
            commenterOnOwnersWork.muteTargetRoute(isLoggedIn: true, currentUsername: "WorkOwner")
        )
        #expect(route.username == "Avery_Archive")

        var handlers = CommentThreadHandlers.noop
        handlers.onMute = { _ in }
        let menu = CommentMenuItems(
            comment: commenterOnOwnersWork,
            isLoggedIn: true,
            currentUsername: "WorkOwner",
            showsReply: true,
            handlers: handlers
        )
        #expect(Self.renderedMenuContains("Mute Avery Writes", in: menu))
    }

    @Test func muteItemTargetsSameConfirmRouteAsOtwarchiveAndProfile() throws {
        let comment = Self.makeComment(
            author: "Avery Writes",
            userPath: "/users/Avery_Archive/pseuds/Avery%20Writes"
        )
        let route = try #require(
            comment.muteTargetRoute(isLoggedIn: true, currentUsername: "Reader")
        )
        #expect(route.username == "Avery_Archive")
        #expect(route.pseud == "Avery Writes")

        let action = CommentsView.muteAction(for: route, by: "Reader")
        #expect(action.kind == .mute)
        #expect(action.url.path == "/users/Reader/muted/users/confirm_mute")
        let components = try #require(URLComponents(url: action.url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "muted_id", value: "Avery_Archive")])

        var handlers = CommentThreadHandlers.noop
        handlers.onMute = { _ in }
        let menu = CommentMenuItems(
            comment: comment,
            isLoggedIn: true,
            currentUsername: "Reader",
            showsReply: true,
            handlers: handlers
        )
        #expect(Self.renderedMenuContains("Mute Avery Writes", in: menu))
    }

    @Test func commentMuteFlowReachesSubmitSuccessWithoutReloadingProfileHeader() async throws {
        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        await auth.login(username: "Reader", password: "pw")

        let comment = Self.makeComment(
            author: "Avery Writes",
            userPath: "/users/Avery_Archive/pseuds/Avery%20Writes"
        )
        let route = try #require(
            comment.muteTargetRoute(isLoggedIn: true, currentUsername: "Reader")
        )
        let action = CommentsView.muteAction(for: route, by: "Reader")
        let confirmHTML = try Self.fixture("ao3_author_confirm_mute")

        var loadedURLs: [URL] = []
        var submittedForms: [AO3AuthorModerationForm] = []
        let commentModel = AO3AuthorProfileModel(
            route: route,
            reloadsHeaderAfterModeration: false,
            pageLoader: { url, _, _ in
                loadedURLs.append(url)
                return AO3AuthorProfileFetcher.Page(html: confirmHTML, isStale: false)
            },
            moderationSubmitter: { form, _ in
                submittedForms.append(form)
                return form.kind.successMessage
            }
        )

        await commentModel.beginModeration(action: action, auth: auth)
        #expect(commentModel.pendingModerationForm?.kind == .mute)
        commentModel.moderationAlertDidDismiss()
        await commentModel.confirmPendingModeration(auth: auth)

        #expect(submittedForms.count == 1)
        #expect(submittedForms.first?.actionURL.path == "/users/me/muted/users")
        #expect(commentModel.actionMessage == "Muted.")
        #expect(loadedURLs == [action.url])

        // Contrast with profile Mute (`reloadsHeaderAfterModeration: true`):
        // its success path must still reload the author dashboard afterward.
        var profileURLs: [URL] = []
        let profileModel = AO3AuthorProfileModel(
            route: route,
            reloadsHeaderAfterModeration: true,
            pageLoader: { url, _, _ in
                profileURLs.append(url)
                return AO3AuthorProfileFetcher.Page(html: confirmHTML, isStale: false)
            },
            moderationSubmitter: { form, _ in
                form.kind.successMessage
            }
        )
        await profileModel.beginModeration(action: action, auth: auth)
        profileModel.moderationAlertDidDismiss()
        await profileModel.confirmPendingModeration(auth: auth)
        #expect(profileModel.actionMessage == "Muted.")
        #expect(profileURLs == [action.url, route.dashboardURL])
    }

    @Test func commentMuteFlowSurfacesRejectionFailure() async throws {
        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        await auth.login(username: "Reader", password: "pw")

        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let action = CommentsView.muteAction(for: route, by: "Reader")
        var loadedURLs: [URL] = []
        let model = AO3AuthorProfileModel(
            route: route,
            reloadsHeaderAfterModeration: false
        ) { url, _, _ in
            loadedURLs.append(url)
            throw AO3WriteError.rejected("You have already muted this user.")
        }

        await model.beginModeration(action: action, auth: auth)

        #expect(loadedURLs == [action.url])
        #expect(model.pendingModerationForm == nil)
        #expect(model.actionMessage == "You have already muted this user.")
    }
}
