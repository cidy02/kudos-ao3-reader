import Foundation
import Testing
@testable import Kudos

@MainActor
struct AppRouterTests {
    @Test func unmungesTagSlug() {
        #expect(AppRouter.unmungeTag("Kara%20Danvers*s*Lena%20Luthor") == "Kara Danvers/Lena Luthor")
        #expect(AppRouter.unmungeTag("Fluff") == "Fluff")
        #expect(AppRouter.unmungeTag("Tony*a*Pepper") == "Tony&Pepper")
    }

    @Test func tagLinkRoutesToNativeTagWorks() {
        let router = AppRouter()
        router.openAO3Link(URL(string: "https://archiveofourown.org/tags/Fluff/works")!)
        #expect(router.pendingTagWorks?.title == "Fluff")
        #expect(router.selection == .browse)
        #expect(router.pendingURL == nil)
    }

    @Test func nonTagAO3LinkFallsBackToWeb() {
        let router = AppRouter()
        router.openAO3Link(URL(string: "https://archiveofourown.org/users/someone")!)
        #expect(router.pendingTagWorks == nil)
        #expect(router.pendingURL != nil)
        #expect(router.selection == .browse)
    }
}
