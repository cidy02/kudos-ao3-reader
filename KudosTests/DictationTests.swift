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

    @Test func emptyStringValuesStillCountAsPresent() {
        let info = bothKeys(microphoneValue: "", speechValue: "")
        let offered = DictationOffer.isOffered(infoDictionary: info, supportsOnDeviceRecognition: true)
        #expect(offered)
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
