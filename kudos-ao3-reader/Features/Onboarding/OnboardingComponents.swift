import SwiftUI

/// Shared first-launch onboarding scaffold — theme-aware background, a scrolling
/// intro area, and a bottom action bar with matching padding/width. Used by
/// `WelcomeView` and `SyncFolderOnboardingView`.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            footer
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 22)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .background(.bar)
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
}

/// One icon+title+body row in an onboarding intro list. Shared by `WelcomeView`
/// and `SyncFolderOnboardingView`.
struct OnboardingPointRow: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
