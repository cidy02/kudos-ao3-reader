import SwiftUI

/// Shared themed layout for first-launch screens. At accessibility sizes the
/// content and actions scroll together so all rows remain reachable.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    var introSpacing: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat
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
        VStack(spacing: introSpacing) {
            content
        }
        .padding(.horizontal, 32)
        .padding(.top, topInset)
        .padding(.bottom, 24)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
    }

    private var pinnedFooter: some View {
        footer
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
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
            buttonBorderShape(.roundedRectangle(radius: SubjectMetrics.cornerRadius))
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
    var iconWidth: CGFloat = 36
    var horizontalSpacing: CGFloat = 16
    var messageFont: Font = .subheadline

    var body: some View {
        HStack(alignment: .top, spacing: horizontalSpacing) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message)
                    .font(messageFont)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
