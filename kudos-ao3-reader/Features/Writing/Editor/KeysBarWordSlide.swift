import CoreGraphics
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Distance-to-words rule for a horizontal slide on `WritingKeysBar` (`Phone-Cursor.dc.html`).
///
/// One word per `pointsPerWord` of travel. `travel` is a distance in points and `direction`
/// is the sign (+ forward, − back). `carried` is the signed leftover from the previous
/// sample, so a slide that stops between words continues from there.
nonisolated enum KeysBarWordSlide {
    static let pointsPerWord: CGFloat = 22

    struct Outcome: Equatable, Sendable {
        var wordSteps: Int
        var remainder: CGFloat
    }

    static func resolve(travel: CGFloat, direction: Int, carried: CGFloat = 0) -> Outcome {
        let distance = abs(travel)
        guard distance > 0, direction != 0 else {
            return Outcome(wordSteps: 0, remainder: carried)
        }
        let sign: CGFloat = direction > 0 ? 1 : -1
        let signed = distance * sign + carried
        let steps = Int(signed / pointsPerWord)
        let remainder = signed - CGFloat(steps) * pointsPerWord
        return Outcome(wordSteps: steps, remainder: remainder)
    }
}

/// Tracks pan translation and touch count across a horizontal keys-bar slide.
///
/// Once two fingers touch the bar, selection extension stays latched for the rest of the gesture
/// so lifting one finger slightly before the other never collapses the selection. Any touch-count
/// transition absorbs UIKit's touch-centroid jump instead of emitting a spurious word step.
nonisolated struct KeysBarWordSlideTracker: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        var delta: CGFloat
        var extend: Bool
    }

    private(set) var lastTranslation: CGFloat = 0
    private(set) var lastTouchCount = 0
    private(set) var isSelecting = false

    mutating func begin(translation: CGFloat, touchCount: Int) -> Sample {
        lastTranslation = translation
        lastTouchCount = max(touchCount, 1)
        isSelecting = touchCount >= 2
        return Sample(delta: translation, extend: isSelecting)
    }

    mutating func change(translation: CGFloat, touchCount: Int) -> Sample {
        let count = touchCount > 0 ? touchCount : lastTouchCount
        if count >= 2 {
            isSelecting = true
        }
        if lastTouchCount > 0, count != lastTouchCount {
            lastTouchCount = count
            lastTranslation = translation
            return Sample(delta: 0, extend: isSelecting)
        }
        let delta = translation - lastTranslation
        lastTranslation = translation
        lastTouchCount = count
        return Sample(delta: delta, extend: isSelecting)
    }

    mutating func end() {
        lastTranslation = 0
        lastTouchCount = 0
        isSelecting = false
    }
}

/// What the keys bar may do for this lane. Defaults do nothing, so every existing bar stays as it is.
struct WritingKeysBarPhoneActions {
    var wordSlideEnabled = false
    var showsDictate = false
    /// True while the dictation panel has replaced the keyboard, so the SwiftUI bar gets out of the way.
    var suppressesKeys = false
    var onMoveByWord: (Int, Bool) -> Void = { _, _ in }
    var onDictate: () -> Void = {}

    static let disabled = WritingKeysBarPhoneActions()
}

private struct WritingKeysBarPhoneKey: EnvironmentKey {
    static let defaultValue = WritingKeysBarPhoneActions.disabled
}

extension EnvironmentValues {
    var writingKeysBarPhone: WritingKeysBarPhoneActions {
        get { self[WritingKeysBarPhoneKey.self] }
        set { self[WritingKeysBarPhoneKey.self] = newValue }
    }
}

struct KeysBarSlideState: Equatable {
    var active = false
    var onTrackRow = false
    var remainder: CGFloat = 0
    var fraction: CGFloat = 0.5
}

/// The track drawn while a slide is in progress, and the large-text / VoiceOver row that keeps
/// word movement off the scrolling keys.
struct KeysBarWordSlideTrack: View {
    var fraction: CGFloat
    var isDragging: Bool
    var onAdjust: (Int) -> Void

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill

    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }

    var body: some View {
        HStack(spacing: 10) {
            Text("‹‹")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            track
            Text("››")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDragging ? "Moving by word" : "Move the cursor by word")
        .accessibilityValue(isDragging ? "Lift to stop" : "")
        .accessibilityHint("Swipe up for the next word. Swipe down for the previous word.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdjust(1)
            case .decrement: onAdjust(-1)
            default: break
            }
        }
    }

    private var track: some View {
        Text(isDragging ? "Moving by word · lift to stop" : "Move by word")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .overlay {
                if isDragging {
                    GeometryReader { proxy in
                        let clamped = min(1, max(0, fraction))
                        let radius: CGFloat = 15
                        let usable = max(0, proxy.size.width - radius * 2)
                        let thumbX = radius + clamped * usable
                        Circle()
                            .fill(effectiveTint.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle().stroke(effectiveTint.opacity(0.18), lineWidth: 6)
                            }
                            .position(x: thumbX, y: proxy.size.height / 2)
                    }
                    .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func keysBarWordSlideGesture(
        enabled: Bool,
        onSample: @escaping (CGFloat, CGFloat, Bool, Bool) -> Void
    ) -> some View {
        modifier(KeysBarWordSlideGestureModifier(enabled: enabled, onSample: onSample))
    }
}

private struct KeysBarWordSlideGestureModifier: ViewModifier {
    var enabled: Bool
    var onSample: (CGFloat, CGFloat, Bool, Bool) -> Void
    @State private var lastTranslation: CGFloat = 0
    @State private var horizontalLocked: Bool?
    @State private var width: CGFloat = 1

    func body(content: Content) -> some View {
        let measured = content.background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, newWidth in
                        width = max(newWidth, 1)
                    }
            }
        }
        #if os(iOS)
        measured.gesture(
            KeysBarWordSlidePan(isEnabled: enabled, viewWidth: width, onSample: onSample)
        )
        #else
        measured
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        if horizontalLocked == nil {
                            horizontalLocked = abs(value.translation.width) > abs(value.translation.height)
                        }
                        guard horizontalLocked == true else { return }
                        let delta = value.translation.width - lastTranslation
                        lastTranslation = value.translation.width
                        let fraction = min(1, max(0, value.location.x / width))
                        onSample(delta, fraction, false, false)
                    }
                    .onEnded { _ in
                        let wasActive = horizontalLocked == true
                        lastTranslation = 0
                        horizontalLocked = nil
                        if wasActive {
                            onSample(0, 0.5, false, true)
                        }
                    },
                isEnabled: enabled
            )
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled {
                    lastTranslation = 0
                    horizontalLocked = nil
                }
            }
        #endif
    }
}

#if os(iOS)
/// Horizontal pan on the keys bar. One finger moves the caret; two fingers extend the selection.
/// A tap never begins the pan, so the keys still receive their taps.
private struct KeysBarWordSlidePan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var viewWidth: CGFloat
    var onSample: (CGFloat, CGFloat, Bool, Bool) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var tracker = KeysBarWordSlideTracker()

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            if velocity.x != 0 || velocity.y != 0 {
                return abs(velocity.x) > abs(velocity.y)
            }
            let translation = pan.translation(in: view)
            return abs(translation.x) > abs(translation.y)
        }
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = true
        pan.isEnabled = isEnabled
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        if recognizer.isEnabled != isEnabled {
            recognizer.isEnabled = isEnabled
        }
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.localTranslation?.x ?? 0
        let width = max(viewWidth, 1)
        let fraction = min(1, max(0, context.converter.localLocation.x / width))
        switch recognizer.state {
        case .began:
            let sample = context.coordinator.tracker.begin(
                translation: translation,
                touchCount: recognizer.numberOfTouches
            )
            onSample(sample.delta, fraction, sample.extend, false)
        case .changed:
            let sample = context.coordinator.tracker.change(
                translation: translation,
                touchCount: recognizer.numberOfTouches
            )
            onSample(sample.delta, fraction, sample.extend, false)
        case .ended, .cancelled, .failed:
            context.coordinator.tracker.end()
            onSample(0, fraction, false, true)
        default:
            break
        }
    }
}
#endif
