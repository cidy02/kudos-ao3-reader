import SwiftUI

/// Shared first-launch onboarding scaffold — a scrolling intro area over a
/// themed base background, and a bottom action bar on the themed raised surface
/// with matching padding/width. Both surfaces follow the app theme (including
/// Sepia). Used by `WelcomeView` and `SyncFolderOnboardingView`.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Pinned under the header, the footer filled the phone and the feature
            // rows never came on screen (AX5). The actions scroll after the rows.
            ScrollView {
                VStack(spacing: 0) {
                    scrollingIntro
                    pinnedFooter
                }
            }
            .background(backgroundColor.ignoresSafeArea())
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    scrollingIntro
                }
                pinnedFooter
            }
            .background(backgroundColor.ignoresSafeArea())
        }
    }

    private var scrollingIntro: some View {
        VStack(spacing: 28) {
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
    }

    private var pinnedFooter: some View {
        footer
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 22)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
            // The themed raised surface, not `.bar`: a system material resolves
            // to its own near-white chrome and ignores the app theme entirely,
            // so under Sepia this bar rendered solid white against the warm
            // cream page above it (owner-reported). `cardSurface` is the
            // codebase's existing token for exactly this — its
            // `appElevatedBackground` doc calls out "list/form cells, bars,
            // popovers" — and it keeps the same one-step lift over
            // `backgroundColor` that `.bar` provided, while falling back to
            // `secondarySystemGroupedBackground`/`controlBackgroundColor` on
            // Light/Dark where no custom theme colour exists. Nothing is lost
            // by dropping the material: this footer is a sibling *below* the
            // ScrollView in the VStack, never an overlay, so no content ever
            // scrolls behind it for the blur to reveal.
            .background(theme.appTheme.cardSurface)
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

extension View {
    /// A capsule clips a second line ("Choose S…"). Accessibility sizes use a
    /// rounded rect; every other size keeps the button's own shape.
    @ViewBuilder
    func onboardingWrapsButton(at accessibilitySize: Bool) -> some View {
        if accessibilitySize {
            buttonBorderShape(.roundedRectangle(radius: 14))
        } else {
            self
        }
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
