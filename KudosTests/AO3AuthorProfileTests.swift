import Foundation
import Testing
@testable import Kudos

@MainActor
struct AO3AuthorIdentityTests {
    @Test func parsesUserAndPercentEncodedPseudRoutes() throws {
        let user = try #require(AO3AuthorRoute(path: "/users/Avery_Archive"))
        #expect(user.username == "Avery_Archive")
        #expect(user.pseud == nil)
        #expect(user.dashboardURL.absoluteString
            == "https://archiveofourown.org/users/Avery_Archive")

        let pseud = try #require(AO3AuthorRoute(
            path: "/users/Avery_Archive/pseuds/Avery%20Writes"
        ))
        #expect(pseud.username == "Avery_Archive")
        #expect(pseud.pseud == "Avery Writes")
        #expect(pseud.pseudURL?.absoluteString
            == "https://archiveofourown.org/users/Avery_Archive/pseuds/Avery%20Writes")
        #expect(pseud.contentURL(.works, page: 2).absoluteString
            == "https://archiveofourown.org/users/Avery_Archive/pseuds/Avery%20Writes/works?page=2")
    }

    @Test func rejectsMalformedReservedAndOffSiteRoutes() {
        #expect(AO3AuthorRoute(path: "/users/") == nil)
        #expect(AO3AuthorRoute(path: "/users/login") == nil)
        #expect(AO3AuthorRoute(path: "/users/Avery_Archive/readings") == nil)
        #expect(AO3AuthorRoute(path: "/users/Avery_Archive/profile/edit") == nil)
        #expect(AO3AuthorRoute(
            path: "/users/Avery_Archive/pseuds/Avery%20Writes/preferences"
        ) == nil)
        #expect(AO3AuthorRoute(
            url: URL(string: "https://example.com/users/Avery_Archive")!
        ) == nil)
    }

    @Test func preservesOrphanAndNonNavigableIdentitySemantics() throws {
        let orphanRoute = try #require(AO3AuthorRoute(
            path: "/users/orphan_account/pseuds/orphan_account"
        ))
        let orphan = AO3AuthorIdentity(route: orphanRoute)
        #expect(orphan.kind == .orphaned)
        #expect(orphan.isNavigable)

        let anonymous = AO3AuthorIdentity.nonNavigable("Anonymous", kind: .anonymous)
        let deleted = AO3AuthorIdentity.nonNavigable("Deleted user", kind: .deleted)
        #expect(!anonymous.isNavigable)
        #expect(!deleted.isNavigable)
        #expect(anonymous.route == nil)
        #expect(deleted.route == nil)
    }

    @Test func verifiedIdentityCodecRoundTripsAndOldLocalWorkDefaultsEmpty() throws {
        let route = try #require(AO3AuthorRoute(
            username: "Avery_Archive",
            pseud: "Avery Writes"
        ))
        let identity = AO3AuthorIdentity(route: route, displayName: "Avery Writes")
        let encoded = AO3AuthorIdentityCodec.encode([identity])
        #expect(AO3AuthorIdentityCodec.decode(encoded) == [identity])
        #expect(AO3AuthorIdentityCodec.decode("not-json").isEmpty)

        let work = SavedWork(title: "Old Import", author: "Avery Writes, Someone Else")
        #expect(work.verifiedAuthorIdentities.isEmpty)
        work.verifiedAuthorIdentities = [identity]
        #expect(work.verifiedAuthorIdentities == [identity])
    }

    @Test func bylineResolvesEachVerifiedCoauthorWithoutGuessingFallbackText() throws {
        let first = AO3AuthorIdentity(
            route: try #require(AO3AuthorRoute(
                username: "Avery_Archive",
                pseud: "Avery Writes"
            ))
        )
        let second = AO3AuthorIdentity(
            route: try #require(AO3AuthorRoute(
                username: "SecondAccount",
                pseud: "Second Pseud"
            ))
        )
        let tokens = AO3AuthorBylineResolver.tokens(
            names: ["Avery Writes", "Second Pseud"],
            identities: [first, second],
            fallbackText: ""
        )
        #expect(tokens.map(\.route?.username) == ["Avery_Archive", "SecondAccount"])
        #expect(tokens.map(\.route?.pseud) == ["Avery Writes", "Second Pseud"])

        let unverified = AO3AuthorBylineResolver.tokens(
            names: [],
            identities: [],
            fallbackText: "Local Name, Not Two Guessed Users"
        )
        #expect(unverified.map(\.name) == ["Local Name, Not Two Guessed Users"])
        #expect(unverified.allSatisfy { $0.route == nil })

        let anonymous = AO3AuthorBylineResolver.tokens(
            names: ["Anonymous"],
            identities: [.nonNavigable("Anonymous", kind: .anonymous)],
            fallbackText: ""
        )
        #expect(anonymous.allSatisfy { $0.route == nil })
    }
}

@MainActor
struct AO3AuthorProfileParserTests {
    final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesUserDashboardAvatarPseudsFandomsAndSignedInActions() throws {
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let header = try AO3Client.parseAuthorDashboard(
            fixture("ao3_author_dashboard"),
            route: route
        )

        #expect(header.identity.route == route)
        #expect(header.identity.avatarURL?.absoluteString
            == "https://archiveofourown.org/images/skins/iconsets/default/icon_user.png")
        #expect(header.identity.userID == 4242)
        #expect(header.pseuds.map(\.name) == ["Avery Writes", "NightShift"])
        #expect(header.fandoms.map(\.name) == ["Star Wars", "The Locked Tomb"])
        #expect(header.fandoms.map(\.workCount) == [12, 3])
        #expect(header.subscriptionForm?.label == "Subscribe")
        #expect(header.subscriptionForm?.csrfToken == "author-fixture-csrf-token")
        #expect(header.subscriptionForm?.isSubscribed == false)
        #expect(header.actions.contains { $0.kind == .mute })
        #expect(header.actions.contains { $0.kind == .block })
        #expect(!header.actions.contains {
            $0.kind == .pseuds && $0.url.path.contains("/pseuds/Avery")
        })
    }

    @Test func parsesBlockAndUnmuteConfirmFormsFromAO3Pages() throws {
        let referer = URL(string: "https://archiveofourown.org/users/Avery_Archive/blocked/confirm")!
        // Same contract as subscription forms: CSRF + action + fields + labels.
        let block = try AO3Client.parseAuthorModerationForm(
            try fixture("ao3_author_confirm_block"),
            referer: referer,
            webKind: .block,
            targetUsername: "Avery_Archive"
        )
        #expect(block.kind == .block)
        #expect(block.title == "Block Avery_Archive")
        #expect(block.submitLabel == "Yes, Block User")
        #expect(block.cancelLabel == "Cancel")
        #expect(block.csrfToken == "moderation-csrf-token")
        #expect(block.actionURL.path == "/users/me/blocked/users")
        #expect(block.fields.contains { $0.name == "blocked_id" && $0.value == "Avery_Archive" })
        #expect(!block.kind.isUndo)
        // Full AO3 copy, structured for an alert (paragraphs + bullet lines).
        #expect(block.message.contains("commenting or leaving kudos"))
        #expect(block.message.contains("• commenting or leaving kudos on your works"))
        #expect(block.message.contains("• hide their works or bookmarks from you"))
        #expect(block.message.contains("Muted Users"))
        #expect(block.message.contains("\n\n"))

        let unmute = try AO3Client.parseAuthorModerationForm(
            try fixture("ao3_author_confirm_unmute"),
            referer: referer,
            webKind: .mute,
            targetUsername: "Avery_Archive"
        )
        #expect(unmute.kind == .unmute)
        #expect(unmute.title == "Unmute Avery_Archive")
        #expect(unmute.submitLabel == "Yes, Unmute User")
        #expect(unmute.actionURL.path == "/users/me/muted/users/99")
        #expect(unmute.fields.contains { $0.name == "_method" && $0.value == "delete" })
        #expect(unmute.kind.isUndo)
        #expect(unmute.kind.successMessage == "Unmuted.")
        #expect(unmute.message.contains("• seeing their works, series, bookmarks, and comments"))
    }

    @Test func moderationConfirmPageFlashErrorsAreSurfaced() throws {
        let referer = URL(string: "https://archiveofourown.org/users/Avery_Archive/blocked/confirm")!
        let html = try fixture("ao3_author_confirm_block_rejected")
        #expect(throws: AO3WriteError.self) {
            try AO3Client.parseAuthorModerationForm(
                html,
                referer: referer,
                webKind: .block,
                targetUsername: "Avery_Archive"
            )
        }
    }

    @Test func parsesPseudDashboardWithoutInventingAvatarOrAuthActions() throws {
        let route = try #require(AO3AuthorRoute(
            username: "Avery_Archive",
            pseud: "Avery Writes"
        ))
        let header = try AO3Client.parseAuthorDashboard(
            fixture("ao3_author_pseud_dashboard"),
            route: route
        )

        #expect(header.identity.route == route)
        #expect(header.identity.displayName == "Avery Writes")
        #expect(header.identity.avatarURL == nil)
        #expect(header.subscriptionForm == nil)
        #expect(!header.actions.contains { $0.kind == .mute || $0.kind == .block })
        #expect(header.pseuds.map(\.name) == ["Avery Writes", "NightShift"])
    }

    @Test func parsesProfileMetadataAndSemanticRichText() throws {
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let about = try AO3Client.parseAuthorAbout(
            fixture("ao3_author_profile"),
            route: route
        )
        let runs = about.bio.blocks.flatMap(\.runs)

        #expect(about.profileTitle == "Avery's Archive Profile")
        #expect(about.joinedDate == "12 March 2014")
        #expect(about.userID == 4242)
        #expect(about.pseuds.map(\.name) == ["Avery Writes", "NightShift"])
        #expect(about.bio.blocks.count == 4)
        #expect(about.actions.contains { $0.kind == .pseuds })
        #expect(runs.contains { $0.text.contains("space opera") && $0.isBold })
        #expect(runs.contains { $0.text.contains("quiet mysteries") && $0.isItalic })
        #expect(runs.contains {
            $0.text.contains("my site") && $0.link?.absoluteString
                == "https://example.com/reading-order"
        })
        #expect(runs.contains { $0.text.contains("Unsafe links") && $0.link == nil })
    }

    @Test func parsesWorksCoauthorsAnonymousOrphanAndPagination() throws {
        let page = try AO3Client.parseAuthorWorksPage(
            fixture("ao3_author_works"),
            page: 1
        )

        #expect(page.works.count == 3)
        #expect(page.totalPages == 3)
        let coauthored = try #require(page.works.first)
        #expect(coauthored.authors == ["Avery Writes", "Second Pseud"])
        #expect(coauthored.authorIdentities.map(\.route?.pseud)
            == ["Avery Writes", "Second Pseud"])
        #expect(coauthored.authorIdentities.map(\.route?.username)
            == ["Avery_Archive", "SecondAccount"])

        let anonymous = page.works[1]
        #expect(anonymous.authorText == "Anonymous")
        #expect(anonymous.authorIdentities.first?.kind == .anonymous)
        #expect(anonymous.authorIdentities.first?.route == nil)

        let orphan = try #require(page.works[2].authorIdentities.first)
        #expect(orphan.kind == .orphaned)
        #expect(orphan.route?.isOrphanAccount == true)
    }

    @Test func parsesSeriesAndBookmarkMetadata() throws {
        let seriesPage = try AO3Client.parseAuthorSeriesPage(
            fixture("ao3_author_series"),
            page: 1
        )
        let series = try #require(seriesPage.series.first)
        #expect(seriesPage.totalPages == 2)
        #expect(series.id == 321)
        #expect(series.title == "The Dawn Cycle")
        #expect(series.creatorIdentities.first?.route?.pseud == "Avery Writes")
        #expect(series.workCount == 3)
        #expect(series.words == 45678)
        #expect(series.isComplete == true)
        #expect(seriesPage.series[1].creatorNames == ["Anonymous"])
        #expect(seriesPage.series[1].creatorIdentities.first?.kind == .anonymous)
        #expect(seriesPage.series[1].creatorIdentities.first?.route == nil)
        #expect(seriesPage.series[1].isComplete == false)

        let bookmarksPage = try AO3Client.parseAuthorBookmarksPage(
            fixture("ao3_author_bookmarks"),
            page: 1
        )
        #expect(bookmarksPage.totalPages == 4)
        #expect(bookmarksPage.bookmarks.count == 2)
        let recommendation = bookmarksPage.bookmarks[0]
        #expect(recommendation.work.id == 2001)
        #expect(recommendation.isRecommendation)
        #expect(!recommendation.isPrivate)
        #expect(recommendation.tags == ["Favorite"])
        #expect(recommendation.collections == ["Summer Reading"])
        #expect(!recommendation.notes.isEmpty)
        #expect(bookmarksPage.bookmarks[1].isPrivate)
        #expect(bookmarksPage.bookmarks[1].work.authorIdentities.first?.kind == .anonymous)
    }

    @Test func acceptsRecognizedEmptyIndexesButRejectsChangedMarkup() throws {
        let works = try AO3Client.parseAuthorWorksPage(
            "<html><body><ol class='work index group'></ol></body></html>",
            page: 1
        )
        let series = try AO3Client.parseAuthorSeriesPage(
            "<html><body><ul class='series index group'></ul></body></html>",
            page: 1
        )
        let bookmarks = try AO3Client.parseAuthorBookmarksPage(
            "<html><body><ol class='bookmark index group'></ol></body></html>",
            page: 1
        )
        #expect(works.works.isEmpty)
        #expect(series.series.isEmpty)
        #expect(bookmarks.bookmarks.isEmpty)

        #expect(throws: AO3Error.self) {
            try AO3Client.parseAuthorWorksPage("<html><body>Changed</body></html>", page: 1)
        }
        let route = try #require(AO3AuthorRoute(username: "UnavailableUser"))
        #expect(throws: AO3Error.self) {
            try AO3Client.parseAuthorDashboard("<html><body>User not found</body></html>", route: route)
        }
    }
}

@MainActor
struct AO3AuthorProfileStateTests {
    final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func defaultsToWorksLoadsTabsLazilyAndDoesNotRefetchActivePage() async throws {
        let dashboard = try fixture("ao3_author_dashboard")
        let works = try fixture("ao3_author_works")
        let series = try fixture("ao3_author_series")
        let about = try fixture("ao3_author_profile")
        var requests: [URL] = []
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let model = AO3AuthorProfileModel(route: route) { url, _, _ in
            requests.append(url)
            if url.path.hasSuffix("/works") {
                return .init(html: works, isStale: false)
            }
            if url.path.hasSuffix("/series") {
                return .init(html: series, isStale: false)
            }
            if url.path.hasSuffix("/profile") {
                return .init(html: about, isStale: false)
            }
            return .init(html: dashboard, isStale: false)
        }
        let auth = AO3AuthService()

        #expect(model.selectedTab == .works)
        model.activate(auth: auth)
        await model.waitForActiveLoad()
        #expect(requests.map(\.path) == [
            "/users/Avery_Archive",
            "/users/Avery_Archive/works"
        ])
        #expect(model.works.count == 3)
        #expect(model.series.isEmpty)
        #expect(model.about == nil)

        model.activate(auth: auth)
        await model.waitForActiveLoad()
        #expect(requests.count == 2)

        model.selectTab(.series, auth: auth)
        await model.waitForActiveLoad()
        #expect(model.series.count == 2)
        #expect(requests.last?.path == "/users/Avery_Archive/series")

        model.selectTab(.works, auth: auth)
        await model.waitForActiveLoad()
        #expect(requests.count == 3)

        model.selectTab(.about, auth: auth)
        await model.waitForActiveLoad()
        #expect(model.about?.userID == 4242)
        #expect(requests.last?.path == "/users/Avery_Archive/profile")
    }

    @Test func scopeChangeCancelsSupersededLoad() async throws {
        let dashboard = try fixture("ao3_author_dashboard")
        let works = try fixture("ao3_author_works")
        let initial = try #require(AO3AuthorRoute(username: "InitialUser"))
        let slow = try #require(AO3AuthorRoute(username: "SlowUser"))
        let final = try #require(AO3AuthorRoute(username: "FinalUser"))
        var cancelledSlowLoad = false
        let model = AO3AuthorProfileModel(route: initial) { url, _, _ in
            if url.path == "/users/SlowUser" {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    cancelledSlowLoad = true
                    throw error
                }
            }
            if url.path.hasSuffix("/works") {
                return .init(html: works, isStale: false)
            }
            return .init(html: dashboard, isStale: false)
        }
        let auth = AO3AuthService()

        model.selectScope(slow, auth: auth)
        await Task.yield()
        model.selectScope(final, auth: auth)
        await model.waitForActiveLoad()

        #expect(cancelledSlowLoad)
        #expect(model.route == final)
        #expect(model.header?.identity.route == final)
        #expect(model.works.count == 3)
    }

    @Test func tabChangeCancelsAnInFlightRefresh() async throws {
        let dashboard = try fixture("ao3_author_dashboard")
        let works = try fixture("ao3_author_works")
        let series = try fixture("ao3_author_series")
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        var refreshStarted = false
        var refreshWasCancelled = false
        let model = AO3AuthorProfileModel(route: route) { url, _, bypassCache in
            if bypassCache, url.path == "/users/Avery_Archive" {
                refreshStarted = true
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    refreshWasCancelled = true
                    throw error
                }
            }
            if url.path.hasSuffix("/works") {
                return .init(html: works, isStale: false)
            }
            if url.path.hasSuffix("/series") {
                return .init(html: series, isStale: false)
            }
            return .init(html: dashboard, isStale: false)
        }
        let auth = AO3AuthService()
        model.activate(auth: auth)
        await model.waitForActiveLoad()

        let refresh = Task { await model.refresh(auth: auth) }
        while !refreshStarted { await Task.yield() }
        model.selectTab(.series, auth: auth)
        await model.waitForActiveLoad()
        await refresh.value

        #expect(refreshWasCancelled)
        #expect(model.selectedTab == .series)
        #expect(model.series.count == 2)
    }

    @Test func paginationFailurePreservesAlreadyLoadedWorks() async throws {
        let dashboard = try fixture("ao3_author_dashboard")
        let works = try fixture("ao3_author_works")
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let model = AO3AuthorProfileModel(route: route) { url, _, _ in
            if URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name == "page" && $0.value == "2" }) == true {
                throw AO3Error.server(status: 503)
            }
            return .init(
                html: url.path.hasSuffix("/works") ? works : dashboard,
                isStale: false
            )
        }
        let auth = AO3AuthService()

        model.activate(auth: auth)
        await model.waitForActiveLoad()
        let originalIDs = model.works.map(\.id)
        #expect(model.hasMore)

        model.loadMore(auth: auth)
        await model.waitForActiveLoad()

        #expect(model.works.map(\.id) == originalIDs)
        #expect(model.currentPage == 1)
        #expect(model.loadMoreError != nil)
    }

    @Test func cacheSeparatesRoutesPagesAndAuthenticationScopes() async throws {
        let cache = AO3AuthorPageCache(ttl: 1)
        let user = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let pseud = try #require(AO3AuthorRoute(
            username: "Avery_Archive",
            pseud: "Avery Writes"
        ))
        let signedWorks = AO3AuthorPageCache.Key(
            url: user.contentURL(.works),
            authenticationScope: "signed-in:Avery_Archive"
        )
        let signedPageTwo = AO3AuthorPageCache.Key(
            url: user.contentURL(.works, page: 2),
            authenticationScope: "signed-in:Avery_Archive"
        )
        let signedPseud = AO3AuthorPageCache.Key(
            url: pseud.contentURL(.works),
            authenticationScope: "signed-in:Avery_Archive"
        )
        let anonymousWorks = AO3AuthorPageCache.Key(
            url: user.contentURL(.works),
            authenticationScope: "anonymous"
        )
        let now = Date(timeIntervalSince1970: 100)

        #expect(signedWorks != signedPageTwo)
        #expect(signedWorks != signedPseud)
        #expect(signedWorks != anonymousWorks)
        await cache.insert("restricted markup", for: signedWorks, now: now)
        #expect(await cache.value(for: signedWorks, now: now) == "restricted markup")
        #expect(await cache.value(for: anonymousWorks, now: now) == nil)
        #expect(await cache.value(for: signedWorks, now: now.addingTimeInterval(2)) == nil)
        #expect(await cache.staleValue(
            for: signedWorks,
            now: now.addingTimeInterval(2)
        ) == "restricted markup")
        #expect(await cache.staleValue(
            for: signedWorks,
            now: now.addingTimeInterval(25 * 60 * 60)
        ) == nil)

        let bounded = AO3AuthorPageCache(ttl: 60, staleTTL: 120, maxEntries: 1)
        await bounded.insert("page one", for: signedWorks, now: now)
        await bounded.insert("page two", for: signedPageTwo, now: now.addingTimeInterval(1))
        #expect(await bounded.staleValue(for: signedWorks, now: now.addingTimeInterval(1)) == nil)
        #expect(await bounded.value(for: signedPageTwo, now: now.addingTimeInterval(1)) == "page two")

        let dashboardCache = AO3AuthorPageCache(ttl: 60, staleTTL: 120, maxEntries: 8)
        let signedDashboard = AO3AuthorPageCache.Key(
            url: user.dashboardURL,
            authenticationScope: "signed-in:Avery_Archive"
        )
        let signedPseudDashboard = AO3AuthorPageCache.Key(
            url: pseud.dashboardURL,
            authenticationScope: "signed-in:Avery_Archive"
        )
        await dashboardCache.insert("user dashboard", for: signedDashboard, now: now)
        await dashboardCache.insert("pseud dashboard", for: signedPseudDashboard, now: now)
        await dashboardCache.insert("works", for: signedWorks, now: now)
        await dashboardCache.removeAuthorDashboards(
            username: "Avery_Archive",
            authenticationScope: "signed-in:Avery_Archive"
        )
        #expect(await dashboardCache.value(for: signedDashboard, now: now) == nil)
        #expect(await dashboardCache.value(for: signedPseudDashboard, now: now) == nil)
        #expect(await dashboardCache.value(for: signedWorks, now: now) == "works")

        let inboxCache = AO3AuthorPageCache(ttl: 60, staleTTL: 120, maxEntries: 8)
        let inboxPageOne = AO3AuthorPageCache.Key(
            url: try #require(AO3Client.inboxURL(username: "Avery_Archive", page: 1)),
            authenticationScope: "signed-in:Avery_Archive"
        )
        let inboxPageTwo = AO3AuthorPageCache.Key(
            url: try #require(AO3Client.inboxURL(username: "Avery_Archive", page: 2)),
            authenticationScope: "signed-in:Avery_Archive"
        )
        let otherScopeInbox = AO3AuthorPageCache.Key(
            url: inboxPageOne.url,
            authenticationScope: "signed-in:Someone_Else"
        )
        await inboxCache.insert("page one", for: inboxPageOne, now: now)
        await inboxCache.insert("page two", for: inboxPageTwo, now: now)
        await inboxCache.insert("other account", for: otherScopeInbox, now: now)
        await inboxCache.removePages(
            path: inboxPageOne.url.path,
            authenticationScope: "signed-in:Avery_Archive"
        )
        #expect(await inboxCache.value(for: inboxPageOne, now: now) == nil)
        #expect(await inboxCache.value(for: inboxPageTwo, now: now) == nil)
        #expect(await inboxCache.value(for: otherScopeInbox, now: now) == "other account")
    }
}
