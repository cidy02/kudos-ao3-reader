import Foundation
import ReadiumNavigator
import ReadiumShared

public enum TTSServiceStatus: Equatable {
    case unavailable
    case stopped
    case playing
    case paused
}

/// The public surface of a TTS service that matches the shape expected by ReaderSpeechController.
/// The controller can swap out the Readium synthesizer for an implementation of this protocol.
public protocol TTSService: AnyObject {
    /// The current state of playback.
    var status: TTSServiceStatus { get }

    /// The sentence currently being spoken.
    var spokenText: String { get }

    /// 0...1 instantaneous energy from the current word being spoken (for equalizer).
    var speechEnergy: Double { get }

    /// Random seed representing the current fragment.
    var speechEnergySeed: Double { get }

    /// Voices available from this engine.
    var availableVoices: [TTSVoice] { get }

    /// Callback when the engine's status changes.
    var onStatusChange: ((TTSServiceStatus) -> Void)? { get set }

    /// Callback when the spoken text changes.
    var onSpokenTextChange: ((String) -> Void)? { get set }

    /// Callback when speech energy changes (pulsed per fragment).
    var onSpeechEnergyPulse: ((Double, Double) -> Void)? { get set }

    /// Callback for page syncing.
    var onAdvance: ((Locator) -> Void)? { get set }

    /// Feed a text payload to the service to start speaking from a given locator.
    /// - Parameters:
    ///   - text: The full text content to chunk and speak.
    ///   - startLocator: The locator corresponding to the start of this text.
    func speak(text: String, startLocator: Locator?) async throws

    /// Pauses playback.
    func pause()

    /// Resumes playback.
    func resume()

    /// Stops playback and clears queues.
    func stop()

    /// Updates configuration.
    func setVoice(id: String)
    func setRate(_ rate: Float)
    func setPitch(_ pitch: Float)
}
