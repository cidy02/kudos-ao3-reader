import SwiftUI

/// First-launch welcome screen. Shown once (gated by `hasCompletedOnboarding`)
/// before the main UI. Theme-aware, Dynamic-Type friendly, and accessible — a
/// warm introduction, not a legal wall of text. The full disclaimer and credits
/// live in Settings → About.
struct WelcomeView: View {
    /// Called when the user taps Continue; the host persists completion.
    var onContinue: () -> Void

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
                Text("Welcome to Kudos")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Free to use • Ad-free • Built by fans")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingPointRow(
                symbol: "book", title: "Built for AO3 Readers",
                message: "An unofficial reader for Archive of Our Own. Kudos is free and open "
                    + "source, has no ads, and isn't affiliated with AO3 or the OTW."
            )
            OnboardingPointRow(
                symbol: "lock.shield", title: "Your Privacy Matters",
                message: "Kudos has no ads, analytics, tracking, or hidden data collection. Your "
                    + "AO3 sign-in and the information Kudos needs stay on your device."
            )
            OnboardingPointRow(
                symbol: "heart", title: "Community Built",
                message: "Kudos is made by fans. It doesn't accept donations, but you can "
                    + "contribute to the project."
            )
            OnboardingPointRow(
                symbol: "ladybug", title: "Need Help?",
                message: "Found a bug? Shake your device to send a report, or open an issue on "
                    + "GitHub. The AO3 team can't help with Kudos, so please don't contact them about it."
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if let url = URL(string: AppLinks.repository) {
                Link(destination: url) {
                    Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityHint("Opens the project's source code in your browser")
            }

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .prominentLabel()
            .controlSize(.large)
        }
    }
}
