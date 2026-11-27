#if os(iOS)
import SwiftUI
import UIKit

/// The panel that replaces the keyboard while dictating (`Phone-Dictate.dc.html`).
struct DictationPanel: View {
    var controller: DictationController
    var onUndoPhrase: () -> Void
    var onKeyboard: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(controller.statusLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if !controller.pendingText.isEmpty {
                    Text(controller.pendingText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Still recognizing")
                        .accessibilityValue(controller.pendingText)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                if controller.phase == .listening {
                    DictationLevelMeter(levels: controller.levels, tint: effectiveTint)
                        .accessibilityHidden(true)
                }

                if controller.phase == .requestingPermission {
                    ProgressView()
                        .accessibilityLabel("Asking to listen")
                }

                if showsMicrophone {
                    microphoneButton
                }

                if showsCommands {
                    commandChips
                }

                if controller.phase == .denied {
                    Button(action: openSettings) {
                        Text("Settings")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(effectiveTint)
                    .accessibilityLabel("Open Settings")
                }

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        panelButton("Undo Last Phrase", action: onUndoPhrase)
                        panelButton("Keyboard", action: onKeyboard)
                    }
                } else {
                    HStack(spacing: 10) {
                        panelButton("Undo Last Phrase", action: onUndoPhrase)
                        panelButton("Keyboard", action: onKeyboard)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 520 : 340)
        .background(panelBackground)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation")
    }

    private var showsMicrophone: Bool {
        switch controller.phase {
        case .listening, .stopped, .unavailable: true
        case .idle, .requestingPermission, .denied: false
        }
    }

    private var showsCommands: Bool {
        controller.phase == .listening || controller.phase == .stopped
    }

    private var microphoneButton: some View {
        Button(action: controller.toggleListening) {
            ZStack {
                if controller.phase == .listening, !reduceMotion {
                    Circle()
                        .stroke(effectiveTint.opacity(0.45), lineWidth: 3)
                        .frame(width: 84, height: 84)
                        .phaseAnimator([false, true]) { content, pulse in
                            content
                                .scaleEffect(pulse ? 1.35 : 1)
                                .opacity(pulse ? 0 : 0.7)
                        } animation: { _ in
                            .easeOut(duration: 1.6)
                        }
                        .accessibilityHidden(true)
                }
                Image(systemName: "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(effectiveTint, in: Circle())
            }
            .frame(minWidth: 84, minHeight: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(controller.phase == .listening ? "Stop dictating" : "Start dictating")
    }

    private var commandChips: some View {
        FlowLayout(spacing: 6, rowSpacing: 6, rowAlignment: .center) {
            ForEach(DictationCommand.allCases, id: \.self) { command in
                Text("Say “\(command.spoken)”")
                    .font(.footnote)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .accessibilityLabel("Say \(command.spoken)")
            }
        }
    }

    private func panelButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if let elevated = appTheme.appElevatedBackground {
            elevated
        } else {
            Rectangle().fill(.background)
        }
    }
}

private struct DictationLevelMeter: View {
    var levels: [CGFloat]
    var tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(tint.opacity(0.55))
                    .frame(width: 4, height: 6 + min(1, max(0, level)) * 28)
            }
        }
        .frame(height: 34)
        .animation(.linear(duration: 0.08), value: levels)
    }
}
#endif
