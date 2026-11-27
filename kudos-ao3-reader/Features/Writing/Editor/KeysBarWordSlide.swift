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
    var remainder: CGFloat = 0
    var fraction: CGFloat = 0.5
}

/// The track drawn while a slide is in progress, and the large-text row that keeps word
/// movement off the scrolling keys.
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
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDragging ? "Moving by word" : "Move the cursor by word")
        .accessibilityValue(isDragging ? "Lift to stop" : "Swipe up or down to move one word")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdjust(1)
            case .decrement: onAdjust(-1)
            default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, fraction))
            let thumbX = clamped * proxy.size.width
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Text(isDragging ? "Moving by word · lift to stop" : "Move by word")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                if isDragging {
                    Circle()
                        .fill(effectiveTint.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle().stroke(effectiveTint.opacity(0.18), lineWidth: 6)
                        }
                        .position(x: thumbX, y: proxy.size.height / 2)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder
    func keysBarWordSlideGesture(
        enabled: Bool,
        onSample: @escaping (CGFloat, CGFloat, Int, Bool) -> Void
    ) -> some View {
        if enabled {
            modifier(KeysBarWordSlideGestureModifier(onSample: onSample))
        } else {
            self
        }
    }
}

private struct KeysBarWordSlideGestureModifier: ViewModifier {
    var onSample: (CGFloat, CGFloat, Int, Bool) -> Void
    @State private var lastTranslation: CGFloat = 0
    @State private var width: CGFloat = 1

    func body(content: Content) -> some View {
        #if os(iOS)
        content.gesture(KeysBarWordSlidePan(onSample: onSample))
        #else
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.width, initial: true) { _, newWidth in
                            width = max(newWidth, 1)
                        }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        let delta = value.translation.width - lastTranslation
                        lastTranslation = value.translation.width
                        let fraction = min(1, max(0, value.location.x / width))
                        onSample(delta, fraction, 1, false)
                    }
                    .onEnded { _ in
                        lastTranslation = 0
                        onSample(0, 0.5, 1, true)
                    }
            )
        #endif
    }
}

#if os(iOS)
/// Horizontal pan on the keys bar. One finger moves the caret; two fingers extend the selection.
/// A tap never begins the pan, so the keys still receive their taps.
private struct KeysBarWordSlidePan: UIGestureRecognizerRepresentable {
    var onSample: (CGFloat, CGFloat, Int, Bool) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastTranslation: CGFloat = 0
        var touches = 1

        nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
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
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.localTranslation?.x ?? 0
        let width = max(recognizer.view?.bounds.width ?? 1, 1)
        let fraction = min(1, max(0, context.converter.localLocation.x / width))
        if recognizer.numberOfTouches > 0 {
            context.coordinator.touches = recognizer.numberOfTouches
        }
        switch recognizer.state {
        case .began:
            // `translation` is already the distance that made the pan begin. Count it, then continue from there.
            context.coordinator.lastTranslation = translation
            onSample(translation, fraction, context.coordinator.touches, false)
        case .changed:
            let delta = translation - context.coordinator.lastTranslation
            context.coordinator.lastTranslation = translation
            onSample(delta, fraction, context.coordinator.touches, false)
        case .ended, .cancelled, .failed:
            context.coordinator.lastTranslation = 0
            onSample(0, fraction, context.coordinator.touches, true)
        default:
            break
        }
    }
}
#endif
