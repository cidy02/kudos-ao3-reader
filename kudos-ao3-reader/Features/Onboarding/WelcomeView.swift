import SwiftUI

/// First-launch welcome screen. Shown once (gated by `hasCompletedOnboarding`)
/// before the main UI. Theme-aware, Dynamic-Type friendly, and accessible — a
/// warm introduction, not a legal wall of text. The full disclaimer and credits
/// live in Settings → About.
struct WelcomeView: View {
    /// Called when the user taps Continue; the host persists completion.
    var onContinue: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        OnboardingScaffold(introSpacing: 48, topInset: 18, bottomInset: 6) {
            header
            points
        } footer: {
            footer
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            Image("AppIconArt")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 9, y: 4)
                .accessibilityHidden(true)

            Text("\(Text("Welcome to").foregroundStyle(.primary))\n\(Text("Kudos").foregroundStyle(.accentInk))")
                .font(.largeTitle.weight(.heavy))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingPointRow(
                symbol: "book", title: "Read anywhere",
                message: WelcomeBoardCopy.readAnywhere
            )
            OnboardingPointRow(
                symbol: "heart", title: "All of AO3, native",
                message: "Search, browse fandoms, leave kudos and comments, and keep up with subscriptions."
            )
            OnboardingPointRow(
                symbol: "lock.shield", title: "Yours, on this device",
                message: WelcomeBoardCopy.localLibrary(deviceName: ThisDevice.name)
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Text("Free to use · Ad-free · Built by fans. Kudos is open source and not affiliated with the OTW or AO3.")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onContinue) {
                actionTitle("Continue")
            }
            .buttonStyle(.kudosPrimaryConfirm)
            .onboardingWrapsButton(at: dynamicTypeSize.isAccessibilitySize)

            if let url = URL(string: AppLinks.repository) {
                Link(destination: url) {
                    githubLabel
                }
                .foregroundStyle(.accentInk)
                .accessibilityHint("Opens the project’s source code in your browser")
            }
        }
    }

    @ViewBuilder
    private var githubLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // One line was cut once the type outgrew the row.
            Text("View on GitHub")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        } else {
            Text("View on GitHub").font(.subheadline)
        }
    }

    @ViewBuilder
    private func actionTitle(_ text: String) -> some View {
        let title = Text(text).font(.headline)
        if dynamicTypeSize.isAccessibilitySize {
            title
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        } else {
            title.frame(maxWidth: .infinity)
        }
    }
}

enum WelcomeBoardCopy {
    static var readAnywhere: String {
        #if os(iOS)
        "Download works and read them offline, with themes, fonts and Read Aloud."
        #else
        "Download works and read them offline, with themes and custom fonts."
        #endif
    }

    static func localLibrary(deviceName: String) -> String {
        "Your library, queues and history stay on your \(deviceName)."
            + (deviceName == "iPhone" ? " Mature works can hide behind Face ID." : "")
    }
}
