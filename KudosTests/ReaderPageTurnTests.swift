import Foundation
import Testing
@testable import Kudos

@Suite("Reader page turn")
struct ReaderPageTurnTests {
    private func isolatedDefaults() throws -> UserDefaults {
        let name = "ReaderPageTurnTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultIsSlideAndTheKeyIsReaderPageTurn() throws {
        #expect(ReaderPageTurnStyle.defaultStyle == .slide)
        #expect(ReaderPageTurnStyle.storageKey == "readerPageTurn")
        #expect(ReaderPageTurnStyle.none.title == "None")
        #expect(ReaderPageTurnStyle.slide.title == "Slide")
        #expect(ReaderPageTurnStyle.fade.title == "Fast Fade")
        let defaults = try isolatedDefaults()
        #expect(ReaderPageTurnStyle.stored(in: defaults) == .slide)
    }

    @Test func storedStyleFollowsTheDefaultsKey() throws {
        let defaults = try isolatedDefaults()
        defaults.set(ReaderPageTurnStyle.none.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        #expect(ReaderPageTurnStyle.stored(in: defaults) == .none)
        defaults.set(ReaderPageTurnStyle.slide.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        #expect(ReaderPageTurnStyle.stored(in: defaults) == .slide)
        defaults.set(ReaderPageTurnStyle.curl.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        #expect(ReaderPageTurnStyle.stored(in: defaults) == .curl)
        defaults.set("nope", forKey: ReaderPageTurnStyle.storageKey)
        #expect(ReaderPageTurnStyle.stored(in: defaults) == .slide)
        defaults.removeObject(forKey: ReaderPageTurnStyle.storageKey)
        #expect(ReaderPageTurnStyle.stored(in: defaults) == .slide)
    }

    @Test func pickerOffersNoneSlideFastFadeAndCurl() {
        #expect(ReaderPageTurnStyle.pickerCases == [.none, .slide, .fade, .curl])
        #expect(ReaderPageTurnStyle.allCases == [.none, .slide, .fade, .curl])
        #expect(ReaderPageTurnStyle.curl.title == "Curl")
    }

    @Test func animatedTransitionIsSlideFadeOrCurlInPagedModeOnly() {
        for style in ReaderPageTurnStyle.allCases {
            for mode in ReadingMode.allCases {
                for reduceMotion in [false, true] {
                    let animated = ReaderPageTurnPolicy.animatedTransition(
                        style: style,
                        readingMode: mode,
                        reduceMotion: reduceMotion
                    )
                    let plays = style == .slide || style == .fade || style == .curl
                    let expected = plays && mode == .paged && !reduceMotion
                    #expect(
                        animated == expected,
                        "style \(style.rawValue) mode \(mode.rawValue) reduceMotion \(reduceMotion)"
                    )
                }
            }
        }
    }

    @Test func backupOmitsAnUnsetPageTurnAndLeavesTheLocalChoice() throws {
        let source = try isolatedDefaults()
        let captured = KudosBackupSettings.capture(defaults: source)
        #expect(captured.readerPageTurn == nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(captured)) as? [String: Any]
        #expect(json?["readerPageTurn"] == nil)

        let local = try isolatedDefaults()
        local.set(ReaderPageTurnStyle.none.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        captured.apply(to: local)
        #expect(local.string(forKey: ReaderPageTurnStyle.storageKey) == ReaderPageTurnStyle.none.rawValue)

        let older = "{\"readerMode\":\"paged\"}"
        let decoded = try JSONDecoder().decode(KudosBackupSettings.self, from: Data(older.utf8))
        #expect(decoded.readerPageTurn == nil)
        decoded.apply(to: local)
        #expect(local.string(forKey: ReaderPageTurnStyle.storageKey) == ReaderPageTurnStyle.none.rawValue)
    }

    @Test func backupRoundTripsAChosenPageTurnAndSkipsAnUnknownValue() throws {
        let source = try isolatedDefaults()
        source.set(ReaderPageTurnStyle.none.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        let captured = KudosBackupSettings.capture(defaults: source)
        #expect(captured.readerPageTurn == "none")
        let roundTripped = try JSONDecoder().decode(
            KudosBackupSettings.self,
            from: JSONEncoder().encode(captured)
        )
        #expect(roundTripped.readerPageTurn == "none")

        let destination = try isolatedDefaults()
        destination.set(ReaderPageTurnStyle.slide.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        roundTripped.apply(to: destination)
        #expect(destination.string(forKey: ReaderPageTurnStyle.storageKey) == "none")

        // Curl is a picker case and must survive a backup.
        source.set(ReaderPageTurnStyle.curl.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        KudosBackupSettings.capture(defaults: source).apply(to: destination)
        #expect(destination.string(forKey: ReaderPageTurnStyle.storageKey) == "curl")

        source.set("zigzag", forKey: ReaderPageTurnStyle.storageKey)
        let unknown = KudosBackupSettings.capture(defaults: source)
        #expect(unknown.readerPageTurn == "zigzag")
        destination.set(ReaderPageTurnStyle.slide.rawValue, forKey: ReaderPageTurnStyle.storageKey)
        unknown.apply(to: destination)
        #expect(destination.string(forKey: ReaderPageTurnStyle.storageKey) == "slide")

        let malformed = "{\"readerPageTurn\":3}"
        let decoded = try JSONDecoder().decode(KudosBackupSettings.self, from: Data(malformed.utf8))
        #expect(decoded.readerPageTurn == nil)
    }
}
