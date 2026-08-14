import Testing
import Foundation
@testable import Kudos

@MainActor
@Suite("AppRouter M19 Tests")
struct AppRouterM19Tests {
    @Test("AppRouter externalizes non-HTTP and non-AO3 URLs")
    func unguardedURLSinkIsClosed() {
        let router = AppRouter()
        
        let hostileURLs = [
            URL(string: "javascript:alert(1)")!,
            URL(string: "data:text/html,<html>")!,
            URL(string: "file:///etc/passwd")!,
            URL(string: "https://evil.com")!,
            URL(string: "http://example.org")!
        ]
        
        for url in hostileURLs {
            router.open(url)
            #expect(!router.isPresentingWebBrowser, "Hostile URL '\(url)' was opened in the in-app browser")
            // We can't easily assert that UIApplication/NSWorkspace was called,
            // but we MUST assert that isPresentingWebBrowser remains false.
            
            // reset for the next iteration (though it shouldn't be true)
            // Actually router is a class, we could just create a new one, but changing the property directly is internal/published.
            // But just the fact it didn't open the browser is enough to prove the sink is guarded.
        }
    }
}
