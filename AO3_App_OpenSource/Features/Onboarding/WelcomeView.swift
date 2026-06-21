import SwiftUI

/// First-launch welcome screen. Shown once (gated by `hasCompletedOnboarding`)
/// before the main UI. Theme-aware, Dynamic-Type friendly, and accessible — a
/// warm introduction, not a legal wall of text. The full disclaimer and credits
/// live in Settings → About.
struct WelcomeView: View {
    /// Called when the user taps Continue; the host persists completion.
    var onContinue: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    points
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            footer
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    /// The themed app background, falling back to the platform's default surface
    /// for Light/Dark (where `appBaseBackground` is nil).
    private var backgroundColor: Color {
        if let themed = theme.appTheme.appBaseBackground { return themed }
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
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
            point(
                "book", "Built for AO3 Readers",
                "An unofficial, third-party reader for Archive of Our Own — free, open "
                    + "source, and always ad-free. Not affiliated with AO3 or the OTW."
            )
            point(
                "lock.shield", "Your Privacy Matters",
                "No ads, analytics, tracking, or hidden data collection. Anything the "
                    + "app needs — like your AO3 login — stays on your device."
            )
            point(
                "heart", "Community Built",
                "A labor of love. Donations aren't accepted, but contributions are "
                    + "always welcome."
            )
            point(
                "ladybug", "Need Help?",
                "Found a bug? Shake your device to send a report, or open a GitHub "
                    + "issue. Please don't contact the AO3 team — they can't support this app."
            )
        }
    }

    private func point(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
