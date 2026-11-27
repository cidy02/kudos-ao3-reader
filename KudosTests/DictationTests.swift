#if os(iOS)
import AVFoundation
#endif
import Foundation
import Testing
@testable import Kudos

struct DictationCommandParserTests {
    @Test func wholePhraseIsACommand() {
        let paragraph = DictationCommandParser.parse("new paragraph")
        #expect(paragraph == [.command(.newParagraph)])

        let scene = DictationCommandParser.parse("scene break")
        #expect(scene == [.command(.sceneBreak)])

        let on = DictationCommandParser.parse("italics on")
        #expect(on == [.command(.italicsOn)])

        let off = DictationCommandParser.parse("italics off")
        #expect(off == [.command(.italicsOff)])
    }

    @Test func commandInTheMiddleSplitsTheProse() {
        let segments = DictationCommandParser.parse("and then she left new paragraph the boat")
        #expect(segments == [
            .text("and then she left"),
            .command(.newParagraph),
            .text("the boat"),
        ])
    }

    @Test func caseAndTrailingPunctuationDoNotMatter() {
        let cased = DictationCommandParser.parse("New Paragraph")
        #expect(cased == [.command(.newParagraph)])

        let shouted = DictationCommandParser.parse("ITALICS ON")
        #expect(shouted == [.command(.italicsOn)])

        let period = DictationCommandParser.parse("new paragraph.")
        #expect(period == [.command(.newParagraph)])

        let bang = DictationCommandParser.parse("italics on!")
        #expect(bang == [.command(.italicsOn)])

        let comma = DictationCommandParser.parse("Scene Break,")
        #expect(comma == [.command(.sceneBreak)])

        let kept = DictationCommandParser.parse("She Left new paragraph The Boat")
        #expect(kept == [
            .text("She Left"),
            .command(.newParagraph),
            .text("The Boat"),
        ])
    }

    @Test func aCommandWordInsideALongerWordStaysProse() {
        let paragraphs = DictationCommandParser.parse("paragraphs")
        #expect(paragraphs == [.text("paragraphs")])

        let newParagraphs = DictationCommandParser.parse("new paragraphs")
        #expect(newParagraphs == [.text("new paragraphs")])

        let hyphen = DictationCommandParser.parse("scene-break")
        #expect(hyphen == [.text("scene-break")])

        let singular = DictationCommandParser.parse("italic on")
        #expect(singular == [.text("italic on")])

        let alone = DictationCommandParser.parse("italics")
        #expect(alone == [.text("italics")])

        let possessive = DictationCommandParser.parse("paragraph's")
        #expect(possessive == [.text("paragraph's")])

        let joined = DictationCommandParser.parse("newparagraph")
        #expect(joined == [.text("newparagraph")])
    }

    @Test func punctuationBetweenCommandWordsOrLeadingQuotesStaysProse() {
        let sentenceBoundary = DictationCommandParser.parse("He bought something new. Paragraph two.")
        #expect(sentenceBoundary == [.text("He bought something new. Paragraph two.")])

        let sceneBoundary = DictationCommandParser.parse("That was a great scene. Break it down.")
        #expect(sceneBoundary == [.text("That was a great scene. Break it down.")])

        let commaBetween = DictationCommandParser.parse("new, paragraph")
        #expect(commaBetween == [.text("new, paragraph")])

        let quoted = DictationCommandParser.parse("She said “italics on”")
        #expect(quoted == [.text("She said “italics on”")])

        let ellipsis = DictationCommandParser.parse("and left new paragraph… the boat")
        #expect(ellipsis == [
            .text("and left"),
            .command(.newParagraph),
            .text("the boat"),
        ])
    }

    @Test func severalCommandsInOnePhrase() {
        let segments = DictationCommandParser.parse(
            "and then she left new paragraph the boat scene break italics on ran"
        )
        #expect(segments == [
            .text("and then she left"),
            .command(.newParagraph),
            .text("the boat"),
            .command(.sceneBreak),
            .command(.italicsOn),
            .text("ran"),
        ])
    }
}

struct DictationItalicsTests {
    @Test func onAndOffToggleOnlyWhenTheMarkDiffers() {
        let turnOn = DictationItalics.shouldToggle(isOn: false, command: .italicsOn)
        #expect(turnOn)

        let alreadyOn = DictationItalics.shouldToggle(isOn: true, command: .italicsOn)
        #expect(alreadyOn == false)

        let turnOff = DictationItalics.shouldToggle(isOn: true, command: .italicsOff)
        #expect(turnOff)

        let alreadyOff = DictationItalics.shouldToggle(isOn: false, command: .italicsOff)
        #expect(alreadyOff == false)

        let notItalic = DictationItalics.shouldToggle(isOn: false, command: .newParagraph)
        #expect(notItalic == false)
    }

    @Test func aRepeatedOnDoesNotToggleTwice() {
        let steps = DictationPhrasePlan.steps(
            phrase: "italics on hello italics on",
            italicIsOn: false
        )
        #expect(steps == [.toggleItalic, .text("hello")])
    }

    @Test func commandsAndProseBecomeOrderedSteps() {
        let steps = DictationPhrasePlan.steps(
            phrase: "and then she left new paragraph the boat scene break italics on ran",
            italicIsOn: true
        )
        #expect(steps == [
            .text("and then she left"),
            .newParagraph,
            .text("the boat"),
            .sceneBreak,
            .text("ran"),
        ])
    }
}

struct DictationOfferTests {
    private let microphone = DictationOffer.microphoneUsageDescription
    private let speech = DictationOffer.speechRecognitionUsageDescription

    @Test func bothUsageStringsAndOnDeviceRecognitionOfferDictation() {
        let info = bothKeys(microphoneValue: "Listen on this iPhone", speechValue: "Recognise on this iPhone")
        let offered = DictationOffer.isOffered(infoDictionary: info, supportsOnDeviceRecognition: true)
        #expect(offered)
        let allowed = DictationOffer.infoPlistAllowsDictation(info)
        #expect(allowed)
    }

    @Test func emptyOrWhitespaceValuesHideDictation() {
        let empty = bothKeys(microphoneValue: "", speechValue: "")
        let blankMic = bothKeys(microphoneValue: "   ", speechValue: "Recognise on this iPhone")
        let nonString: [String: Any] = [microphone: true, speech: "Recognise on this iPhone"]
        #expect(DictationOffer.isOffered(infoDictionary: empty, supportsOnDeviceRecognition: true) == false)
        #expect(DictationOffer.isOffered(infoDictionary: blankMic, supportsOnDeviceRecognition: true) == false)
        #expect(DictationOffer.isOffered(infoDictionary: nonString, supportsOnDeviceRecognition: true) == false)
        #expect(DictationOffer.infoPlistAllowsDictation(empty) == false)
        #expect(DictationOffer.infoPlistAllowsDictation(blankMic) == false)
        #expect(DictationOffer.infoPlistAllowsDictation(nonString) == false)
    }

    @Test func aMissingUsageStringHidesDictation() {
        let micOnly: [String: Any] = [microphone: "mic"]
        let speechOnly: [String: Any] = [speech: "speech"]
        let missingMic = DictationOffer.isOffered(infoDictionary: speechOnly, supportsOnDeviceRecognition: true)
        let missingSpeech = DictationOffer.isOffered(infoDictionary: micOnly, supportsOnDeviceRecognition: true)
        #expect(missingMic == false)
        #expect(missingSpeech == false)
        #expect(DictationOffer.infoPlistAllowsDictation(micOnly) == false)
        #expect(DictationOffer.infoPlistAllowsDictation(speechOnly) == false)
    }

    @Test func noDictionaryOrNoOnDeviceModelHidesDictation() {
        let info = bothKeys(microphoneValue: "mic", speechValue: "speech")
        let nilInfo = DictationOffer.isOffered(infoDictionary: nil, supportsOnDeviceRecognition: true)
        let empty = DictationOffer.isOffered(infoDictionary: [:], supportsOnDeviceRecognition: true)
        let noModel = DictationOffer.isOffered(infoDictionary: info, supportsOnDeviceRecognition: false)
        #expect(nilInfo == false)
        #expect(empty == false)
        #expect(noModel == false)
        #expect(DictationOffer.infoPlistAllowsDictation(nil) == false)
        #expect(DictationOffer.infoPlistAllowsDictation([:]) == false)
    }

    private func bothKeys(microphoneValue: String, speechValue: String) -> [String: Any] {
        [microphone: microphoneValue, speech: speechValue]
    }
}

@MainActor
struct DictationPhraseInserterTests {
    @Test func commandsAndProseRunInStrictOrderInRichMode() async {
        let source = FakeSourceEditor(text: "<p>Start</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Start</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )
        let switched = await session.switchToRich()
        #expect(switched == .switched)

        await DictationPhraseInserter.apply(
            "she left scene break italics on the boat italics off",
            to: session
        )

        #expect(transport.commandCalls == [
            .insertPhrase("she left"),
            RichEditorCommandArgs(name: "insertSceneBreak", attrs: ["style": .string("asterism")]),
            RichEditorCommandArgs(name: "toggleMark", attrs: ["mark": .string("italic")]),
            .insertPhrase("the boat"),
            RichEditorCommandArgs(name: "toggleMark", attrs: ["mark": .string("italic")]),
        ])
        session.teardown()
    }

    @Test func htmlModeIgnoresDictatedPhrases() async {
        let source = FakeSourceEditor(text: "<p>Start</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Start</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        await DictationPhraseInserter.apply("italics on hello new paragraph", to: session)
        #expect(transport.commandCalls.isEmpty)
        session.teardown()
    }
}

#if os(iOS)
@MainActor
struct DictationControllerLifecycleTests {
    @Test func presentDoesNothingWithoutBothInfoPlistKeysOrInBackground() {
        let missingKeys = DictationController()
        missingKeys.infoDictionaryProvider = { [:] }
        missingKeys.startRecognitionOverride = { _ in }
        missingKeys.present()
        #expect(missingKeys.phase == .idle)
        #expect(missingKeys.isPresented == false)

        let backgrounded = DictationController()
        backgrounded.infoDictionaryProvider = {
            [
                DictationOffer.microphoneUsageDescription: "Mic",
                DictationOffer.speechRecognitionUsageDescription: "Speech",
            ]
        }
        backgrounded.isBackgrounded = { true }
        backgrounded.startRecognitionOverride = { _ in }
        backgrounded.present()
        #expect(backgrounded.phase == .idle)
        #expect(backgrounded.isPresented == false)
    }

    @Test func finalResultAndLateErrorInsertPhraseOnceAndRestart() async throws {
        let controller = DictationController()
        var started: [Int] = []
        var inserted: [String] = []
        controller.startRecognitionOverride = { started.append($0) }
        controller.onPhrase = { inserted.append($0) }
        controller.beginSimulatedListeningForTesting()
        let firstGen = try #require(started.last)

        controller.processRecognitionEvent(text: "the boat", isFinal: false, hasError: false, generation: firstGen)
        #expect(controller.pendingText == "the boat")

        // Empty `isFinal` (common at the one-minute on-device limit) keeps `pendingText`.
        controller.processRecognitionEvent(text: "", isFinal: true, hasError: false, generation: firstGen)
        // Late error for the old generation must not insert a second time or restart again.
        controller.processRecognitionEvent(text: nil, isFinal: false, hasError: true, generation: firstGen)

        await controller.waitForPendingPhrasesForTesting()
        #expect(inserted == ["the boat"])
        #expect(started.count == 2)
        #expect(controller.phase == .listening)
    }

    @Test func silenceTimerCommitsOnceAndIgnoresLateFinalResult() async throws {
        let controller = DictationController()
        controller.silenceDuration = .milliseconds(10)
        var started: [Int] = []
        var inserted: [String] = []
        controller.startRecognitionOverride = { started.append($0) }
        controller.onPhrase = { inserted.append($0) }
        controller.beginSimulatedListeningForTesting()
        let firstGen = try #require(started.last)

        controller.processRecognitionEvent(
            text: "out past the wall",
            isFinal: false,
            hasError: false,
            generation: firstGen
        )
        for _ in 0..<50 where started.count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        controller.processRecognitionEvent(
            text: "out past the wall",
            isFinal: true,
            hasError: false,
            generation: firstGen
        )

        await controller.waitForPendingPhrasesForTesting()
        #expect(inserted == ["out past the wall"])
        #expect(started.count == 2)
    }

    @Test func transientEmptyPartialDoesNotErasePendingTextAndPauseFlushesOnce() async throws {
        let controller = DictationController()
        var started: [Int] = []
        var inserted: [String] = []
        controller.startRecognitionOverride = { started.append($0) }
        controller.onPhrase = { inserted.append($0) }
        controller.beginSimulatedListeningForTesting()
        let gen = try #require(started.last)

        controller.processRecognitionEvent(text: "slack water", isFinal: false, hasError: false, generation: gen)
        controller.processRecognitionEvent(text: "", isFinal: false, hasError: false, generation: gen)
        #expect(controller.pendingText == "slack water")

        controller.pause()
        controller.pause()
        controller.processRecognitionEvent(text: "slack water", isFinal: true, hasError: false, generation: gen)

        await controller.waitForPendingPhrasesForTesting()
        #expect(inserted == ["slack water"])
        #expect(controller.phase == .stopped)
        #expect(controller.pendingText.isEmpty)
    }

    @Test func interruptionAndDismissRespectPendingPhraseContract() async throws {
        let controller = DictationController()
        var started: [Int] = []
        var inserted: [String] = []
        controller.startRecognitionOverride = { started.append($0) }
        controller.onPhrase = { inserted.append($0) }
        controller.beginSimulatedListeningForTesting()
        let firstGen = try #require(started.last)

        controller.processRecognitionEvent(
            text: "before call",
            isFinal: false,
            hasError: false,
            generation: firstGen
        )
        controller.handleInterruption(typeRaw: AVAudioSession.InterruptionType.began.rawValue)
        await controller.waitForPendingPhrasesForTesting()
        #expect(inserted == ["before call"])
        #expect(controller.phase == .stopped)

        controller.beginSimulatedListeningForTesting()
        let secondGen = try #require(started.last)
        controller.processRecognitionEvent(
            text: "to keyboard",
            isFinal: false,
            hasError: false,
            generation: secondGen
        )
        controller.dismiss(commitPending: true)
        await controller.waitForPendingPhrasesForTesting()
        #expect(inserted == ["before call", "to keyboard"])
        #expect(controller.phase == .idle)

        controller.beginSimulatedListeningForTesting()
        let thirdGen = try #require(started.last)
        controller.processRecognitionEvent(
            text: "discarded on leave",
            isFinal: false,
            hasError: false,
            generation: thirdGen
        )
        controller.dismiss(commitPending: false)
        await controller.waitForPendingPhrasesForTesting()
        #expect(inserted == ["before call", "to keyboard"])
        #expect(controller.phase == .idle)
    }

    @Test func oneMinuteTimeoutRestartsCleanlyWhileRapidFailuresStop() async throws {
        var clock = Date(timeIntervalSinceReferenceDate: 1_000)
        let controller = DictationController()
        controller.now = { clock }
        controller.restartBackoff = .milliseconds(1)
        var started: [Int] = []
        controller.startRecognitionOverride = { started.append($0) }
        controller.beginSimulatedListeningForTesting()

        // Simulate ten 60-second silent timeouts: none count as quick failures.
        for _ in 0..<10 {
            let gen = try #require(started.last)
            clock.addTimeInterval(60)
            controller.processRecognitionEvent(text: nil, isFinal: false, hasError: true, generation: gen)
        }
        #expect(controller.phase == .listening)
        #expect(started.count == 11)

        // Now simulate immediate errors (< 5s with no speech): after 5 quick failures it stops as unavailable.
        for step in 0..<5 {
            let gen = try #require(started.last)
            let before = started.count
            clock.addTimeInterval(0.1)
            controller.processRecognitionEvent(text: nil, isFinal: false, hasError: true, generation: gen)
            if step < 4 {
                for _ in 0..<50 where started.count == before {
                    try? await Task.sleep(for: .milliseconds(10))
                }
            }
        }
        #expect(controller.phase == .unavailable)
    }
}
#endif
