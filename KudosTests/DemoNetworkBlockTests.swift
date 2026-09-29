import Foundation
import Testing
@testable import Kudos

/// The design-review harness must never reach AO3 (owner rule).
@Suite(.serialized) struct DemoNetworkBlockTests {
    @Test func blocksOnlyAO3AndOnlyInDemoRuns() {
        let key = "KudosDemoLibrary"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let ao3 = URLRequest(url: URL(string: "https://archiveofourown.org/works/1")!)
        let ao3Sub = URLRequest(url: URL(string: "https://download.archiveofourown.org/x.epub")!)
        let other = URLRequest(url: URL(string: "https://example.com/")!)

        UserDefaults.standard.set(true, forKey: key)
        #expect(DemoNetworkBlock.canInit(with: ao3))
        #expect(DemoNetworkBlock.canInit(with: ao3Sub))
        #expect(!DemoNetworkBlock.canInit(with: other))

        UserDefaults.standard.set(false, forKey: key)
        #expect(!DemoNetworkBlock.canInit(with: ao3))
    }
}
