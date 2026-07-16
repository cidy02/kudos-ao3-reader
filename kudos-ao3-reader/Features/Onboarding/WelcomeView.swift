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
                Text("Open Source • Ad-Free • Community Built")
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
                message: "An unofficial, third-party reader for Archive of Our Own — free, open "
                    + "source, and always ad-free. Not affiliated with AO3 or the OTW."
            )
            OnboardingPointRow(
                symbol: "lock.shield", title: "Your Privacy Matters",
                message: "No ads, analytics, tracking, or hidden data collection. Anything the "
                    + "app needs — like your AO3 login — stays on your device."
            )
            OnboardingPointRow(
                symbol: "heart", title: "Community Built",
                message: "A labor of love. Donations aren't accepted, but contributions are "
                    + "always welcome."
            )
            OnboardingPointRow(
                symbol: "ladybug", title: "Need Help?",
                message: "Found a bug? Shake your device to send a report, or open a GitHub "
                    + "issue. Please don't contact the AO3 team — they can't support this app."
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
            .controlSize(.large)
        }
    }
}
