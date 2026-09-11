import Foundation
import Testing
@testable import Kudos

/// Pins the site-wide archive URLs used on artboard 1aa (More on AO3).
/// Verifies that exact routes verified on 2026-09-11 against otwarchive routes.rb
/// and live AO3 cannot suffer a typo.
struct AccountMoreOnAO3Tests {
    @Test func siteWideURLsMatchExactArchiveRoutes() {
        #expect(AO3ArchivePage.support.url.absoluteString == "https://archiveofourown.org/support")
        #expect(AO3ArchivePage.reportAbuse.url.absoluteString == "https://archiveofourown.org/abuse_reports/new")
        #expect(AO3ArchivePage.termsOfService.url.absoluteString == "https://archiveofourown.org/tos")
        #expect(AO3ArchivePage.contentPolicy.url.absoluteString == "https://archiveofourown.org/content")
        #expect(AO3ArchivePage.privacyPolicy.url.absoluteString == "https://archiveofourown.org/privacy")
        #expect(AO3ArchivePage.faqs.url.absoluteString == "https://archiveofourown.org/faq")
        #expect(AO3ArchivePage.donate.url.absoluteString == "https://archiveofourown.org/donate")
    }

    @Test func directSiteWideURLBuildingMatchesExactRoutes() {
        #expect(AccountExternalNavCard.siteWideURL(path: "/support")?.absoluteString == "https://archiveofourown.org/support")
        #expect(AccountExternalNavCard.siteWideURL(path: "/abuse_reports/new")?.absoluteString == "https://archiveofourown.org/abuse_reports/new")
        #expect(AccountExternalNavCard.siteWideURL(path: "/tos")?.absoluteString == "https://archiveofourown.org/tos")
        #expect(AccountExternalNavCard.siteWideURL(path: "/content")?.absoluteString == "https://archiveofourown.org/content")
        #expect(AccountExternalNavCard.siteWideURL(path: "/privacy")?.absoluteString == "https://archiveofourown.org/privacy")
        #expect(AccountExternalNavCard.siteWideURL(path: "/faq")?.absoluteString == "https://archiveofourown.org/faq")
        #expect(AccountExternalNavCard.siteWideURL(path: "/donate")?.absoluteString == "https://archiveofourown.org/donate")
    }

    @Test func siteWideURLNormalizesLeadingSlash() {
        #expect(AccountExternalNavCard.siteWideURL(path: "support")?.absoluteString == "https://archiveofourown.org/support")
        #expect(AccountExternalNavCard.siteWideURL(path: "/support")?.absoluteString == "https://archiveofourown.org/support")
    }

    @Test func userScopedURLBuilding() {
        #expect(AccountExternalNavCard.userURL(suffix: "works/drafts", username: "testuser")?.absoluteString == "https://archiveofourown.org/users/testuser/works/drafts")
        #expect(AccountExternalNavCard.userURL(suffix: "", username: "testuser")?.absoluteString == "https://archiveofourown.org/users/testuser")
        #expect(AccountExternalNavCard.userURL(suffix: "works/drafts", username: nil) == nil)
    }
}
