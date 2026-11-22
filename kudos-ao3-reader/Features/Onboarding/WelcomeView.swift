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
        OnboardingScaffold {
            header
            points
        } footer: {
            footer
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image("AppIconArt")
                .resizable()
                .scaledToFit()
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 9, y: 4)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("\(Text("Welcome to").foregroundStyle(.primary))\n\(Text("Kudos").foregroundStyle(.accentInk))")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Free to use • Ad-free • Built by fans")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 22) {
            #if os(iOS)
            let readAnywhereMessage = "Download works and read them offline, with themes, fonts, and Read Aloud."
            #else
            let readAnywhereMessage = "Download works and read them offline, with themes and custom fonts."
            #endif
            OnboardingPointRow(
                symbol: "book", title: "Read anywhere",
                message: readAnywhereMessage
            )
            OnboardingPointRow(
                symbol: "heart", title: "All of AO3, native",
                message: "Search, browse fandoms, leave kudos and comments, and keep up with subscriptions."
            )
            OnboardingPointRow(
                symbol: "lock.shield", title: "Yours, on this device",
                message: "Your library, queues, and history stay on your device. No tracking, "
                    + "and mature works can hide behind Face ID."
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if let url = URL(string: AppLinks.repository) {
                Link(destination: url) {
                    githubLabel
                }
                .accessibilityHint("Opens the project's source code in your browser")
            }

            Button(action: onContinue) {
                actionTitle("Continue")
            }
            .buttonStyle(.kudosPrimaryConfirm)
            .onboardingWrapsButton(at: dynamicTypeSize.isAccessibilitySize)
        }
    }

    @ViewBuilder
    private var githubLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // One line was cut once the type outgrew the row.
            Label {
                Text("View on GitHub")
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .font(.subheadline.weight(.medium))
        } else {
            Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.subheadline.weight(.medium))
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
