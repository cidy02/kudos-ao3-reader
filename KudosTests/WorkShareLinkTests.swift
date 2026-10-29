import Foundation
import Testing
@testable import Kudos

struct WorkShareLinkTests {
    private let file = URL(fileURLWithPath: "/tmp/story.epub")

    @Test func ao3PageWinsOverASourceLinkAndTheFile() {
        let url = WorkShareLink.url(
            ao3WorkID: 42,
            sourceURL: "https://example.com/story",
            epubFileURL: file,
            hasReadableEPUB: true
        )
        #expect(url == AO3AuthService.workURL(42))
    }

    @Test func httpSourceIsUsedWhenTheWorkHasNoAO3Page() {
        let url = WorkShareLink.url(
            ao3WorkID: nil,
            sourceURL: "https://example.com/story",
            epubFileURL: file,
            hasReadableEPUB: true
        )
        #expect(url?.absoluteString == "https://example.com/story")
    }

    @Test func theFileIsUsedWhenNothingIsALink() {
        let url = WorkShareLink.url(
            ao3WorkID: nil,
            sourceURL: "file:///imported.epub",
            epubFileURL: file,
            hasReadableEPUB: true
        )
        #expect(url == file)
    }

    @Test func nothingIsSharedWhenTheFileIsMissingAndThereIsNoLink() {
        let url = WorkShareLink.url(
            ao3WorkID: nil,
            sourceURL: "",
            epubFileURL: file,
            hasReadableEPUB: false
        )
        #expect(url == nil)
    }
}
