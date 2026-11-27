import Foundation
#if os(iOS)
import Speech
#endif

/// Whether Dictate may be offered. Asking for the microphone or speech recognition without the
/// usage strings crashes, and those strings are the owner's to add. On-device recognition is
/// required so nothing leaves the iPhone.
nonisolated enum DictationOffer {
    static let microphoneUsageDescription = "NSMicrophoneUsageDescription"
    static let speechRecognitionUsageDescription = "NSSpeechRecognitionUsageDescription"

    static func infoPlistAllowsDictation(_ info: [String: Any]?) -> Bool {
        guard let info else { return false }
        return hasNonEmptyString(info[microphoneUsageDescription])
            && hasNonEmptyString(info[speechRecognitionUsageDescription])
    }

    static func isOffered(
        infoDictionary: [String: Any]?,
        supportsOnDeviceRecognition: Bool
    ) -> Bool {
        infoPlistAllowsDictation(infoDictionary) && supportsOnDeviceRecognition
    }

    #if os(iOS)
    /// Checks the Info.plist keys before ever touching `SFSpeechRecognizer`.
    static var currentDeviceAllows: Bool {
        guard infoPlistAllowsDictation(Bundle.main.infoDictionary) else { return false }
        return SFSpeechRecognizer()?.supportsOnDeviceRecognition == true
    }
    #endif

    private static func hasNonEmptyString(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
