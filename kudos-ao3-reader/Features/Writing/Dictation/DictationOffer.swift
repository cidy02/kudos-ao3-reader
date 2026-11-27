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
        return info[microphoneUsageDescription] != nil
            && info[speechRecognitionUsageDescription] != nil
    }

    static func isOffered(
        infoDictionary: [String: Any]?,
        supportsOnDeviceRecognition: Bool
    ) -> Bool {
        supportsOnDeviceRecognition && infoPlistAllowsDictation(infoDictionary)
    }

    #if os(iOS)
    /// Device capability, read once. Locales without an on-device model hide Dictate.
    static let deviceSupportsOnDeviceRecognition: Bool = SFSpeechRecognizer()?.supportsOnDeviceRecognition == true

    static var currentDeviceAllows: Bool {
        isOffered(
            infoDictionary: Bundle.main.infoDictionary,
            supportsOnDeviceRecognition: deviceSupportsOnDeviceRecognition
        )
    }
    #endif
}
