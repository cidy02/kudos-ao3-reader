import Foundation
import Testing
@testable import Kudos

/// Pins the edge-case matrix `AO3URLResolver` must handle consistently across the
/// ~10 call sites it consolidates (T-117/PONY-6.1) — none of this behavior was
/// covered by a direct test anywhere before the consolidation.
struct AO3URLResolverTests {
    @Test func nilInputReturnsNil() {
        #expect(AO3URLResolver.resolve(nil) == nil)
    }

    @Test func emptyStringReturnsNil() {
        #expect(AO3URLResolver.resolve("") == nil)
    }

    @Test func whitespaceOnlyReturnsNil() {
        #expect(AO3URLResolver.resolve("   \n\t") == nil)
    }

    @Test func relativePathWithLeadingSlashResolves() {
        #expect(AO3URLResolver.resolve("/works/12345")?.absoluteString == "https://archiveofourown.org/works/12345")
    }

    @Test func relativePathWithoutLeadingSlashResolves() {
        #expect(AO3URLResolver.resolve("works/12345")?.absoluteString == "https://archiveofourown.org/works/12345")
    }

    @Test func queryStringAndFragmentArePreserved() {
        let resolved = AO3URLResolver.resolve("/works/1?page=2#chapter")
        #expect(resolved?.absoluteString == "https://archiveofourown.org/works/1?page=2#chapter")
    }

    @Test func alreadyAbsoluteAO3URLPassesThrough() {
        let resolved = AO3URLResolver.resolve("https://archiveofourown.org/users/alice")
        #expect(resolved?.absoluteString == "https://archiveofourown.org/users/alice")
    }

    @Test func subdomainHostIsAllowedByDefault() {
        #expect(AO3URLResolver.resolve("https://download.archiveofourown.org/works/1") != nil)
    }

    @Test func protocolRelativeSameHostResolves() {
        let resolved = AO3URLResolver.resolve("//archiveofourown.org/works/1")
        #expect(resolved?.absoluteString == "https://archiveofourown.org/works/1")
    }

    @Test func protocolRelativeForeignHostIsRejectedByDefault() {
        #expect(AO3URLResolver.resolve("//evil.example.com/phish") == nil)
    }

    @Test func protocolRelativeForeignHostIsAllowedWithFlag() {
        let resolved = AO3URLResolver.resolve("//example.com/authors/bio", allowExternalHost: true)
        #expect(resolved?.host == "example.com")
    }

    @Test func absoluteForeignHostIsRejectedByDefault() {
        #expect(AO3URLResolver.resolve("https://evil.example.com/works/1") == nil)
    }

    @Test func absoluteForeignHostIsAllowedWithFlag() {
        let resolved = AO3URLResolver.resolve("https://example.com/about", allowExternalHost: true)
        #expect(resolved?.host == "example.com")
    }

    @Test func javascriptSchemeIsAlwaysRejected() {
        #expect(AO3URLResolver.resolve("javascript:alert(1)") == nil)
        #expect(AO3URLResolver.resolve("javascript:alert(1)", allowExternalHost: true) == nil)
    }

    @Test func mailtoSchemeIsAlwaysRejected() {
        #expect(AO3URLResolver.resolve("mailto:someone@example.com") == nil)
        #expect(AO3URLResolver.resolve("mailto:someone@example.com", allowExternalHost: true) == nil)
    }
}
