import SwiftUI

nonisolated enum AO3InvitationRequest {
    static let url = URL(string: "https://archiveofourown.org/invite_requests")!
}

/// AO3 accounts are invitation-based. Keep this as an inline text link on both
/// account entry surfaces so it never reads like an alternate sign-in button.
struct AO3InvitationRequestLink: View {
    let onOpen: () -> Void

    var body: some View {
        Text("No AO3 account? [Create one ↗](\(AO3InvitationRequest.url.absoluteString))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.openURL, OpenURLAction { url in
                guard url == AO3InvitationRequest.url else { return .systemAction }
                onOpen()
                return .handled
            })
            .accessibilityHint("Opens AO3's invitation request page")
    }
}

/// Native AO3 account entry. The WebView used by `AO3AuthService` remains
/// off-screen unless the automatic mechanism fails, at which point this view
/// deliberately switches to the visible fallback.
struct AO3LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager

    @State private var username = ""
    @State private var password = ""
    /// True only when the user tapped Cancel (or left via Create Account / Forgot
    /// Password). Distinguishes intentional abandonment from SwiftUI tearing the
    /// sheet down mid-login — the latter must not cancel an in-flight attempt.
    @State private var userInitiatedClose = false

    private static let passwordResetURL = URL(string: "https://archiveofourown.org/users/password/new")!

    /// Automatic submit or visible AO3 hand-off — swipe-to-dismiss would abandon
    /// credentials mid-flight and surface as "popup closed, still signed out".
    private var blocksInteractiveDismiss: Bool {
        switch auth.status {
        case .signingIn, .usingFallback: true
        default: false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if auth.isUsingFallback {
                    fallbackChrome
                    Divider()
                }

                // One host for the login WKWebView for the whole sheet lifetime.
                // Remounting it when switching native → fallback (old dual-host
                // layout) can interrupt a live navigation and cancel the attempt.
                // Hidden 1×1 keeps a window during the automatic phase so WebKit
                // doesn't throttle an off-screen content process.
                ZStack(alignment: .topLeading) {
                    WebView(webView: auth.loginWebView)
                        // Fixed 1×1 while automatic; expands when the visible fallback
                        // takes over — same representable identity either way.
                        .frame(
                            width: auth.isUsingFallback ? nil : 1,
                            height: auth.isUsingFallback ? nil : 1
                        )
                        .frame(
                            maxWidth: auth.isUsingFallback ? .infinity : nil,
                            maxHeight: auth.isUsingFallback ? .infinity : nil
                        )
                        .opacity(auth.isUsingFallback ? 1 : 0)
                        .allowsHitTesting(auth.isUsingFallback)
                        .accessibilityHidden(!auth.isUsingFallback)

                    if !auth.isUsingFallback {
                        nativeContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Log In to AO3")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        userInitiatedClose = true
                        auth.cancelLogin()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 440)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(blocksInteractiveDismiss)
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if loggedIn {
                password = ""
                dismiss()
            }
        }
        .onChange(of: themeManager.appTheme, initial: true) { _, theme in
            auth.applyFallbackTheme(theme)
        }
        .onDisappear {
            password = ""
            // Explicit Cancel / help-link leave already cancelled (or never started).
            // Do not cancel `.signingIn` here: sheet content can disappear while the
            // automatic submit is still running (nested sheet races, parent re-render,
            // presentation glitches). Canceling that attempt is the main way users
            // see the popup vanish and remain signed out after entering a password.
            // `.usingFallback` is cancelled only on intentional close — swipe is
            // disabled while the visible AO3 page is up.
            if userInitiatedClose {
                return
            }
            switch auth.status {
            case .signingIn, .usingFallback, .signedIn:
                break
            case .signedOut, .restoring:
                auth.cancelLogin()
            }
        }
    }

    private var nativeContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Kudos submits these credentials only to AO3's official login page. "
                        + "Your password is never saved; only the session lives in this device's Keychain.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(themeManager.appTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 0) {
                    LabeledContent("Username") {
                        TextField("or email", text: $username,
                                  prompt: themeManager.appTheme.sepiaPrompt("or email"))
                            .textContentType(.username)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        #endif
                            .submitLabel(.next)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Username or email")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 50)

                    Divider()
                        .padding(.leading, 16)

                    LabeledContent("Password") {
                        SecureField("Password", text: $password,
                                    prompt: themeManager.appTheme.sepiaPrompt("Password"))
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Password")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 50)
                }
                .background(themeManager.appTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))

                if let error = auth.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(themeManager.appTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                }

                loginButton

                Button("Forgot your password?") {
                    openOnAO3(Self.passwordResetURL)
                }
                .foregroundStyle(.accentInk)

                AO3InvitationRequestLink {
                    openOnAO3(AO3InvitationRequest.url)
                }

                Text("These open AO3 in Kudos. Come back here to log in afterwards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .appScreenSurface(.grouped)
    }

    /// Filled accent capsule when enabled. Disabled, an undimmed pale tint keeps
    /// the label readable in every theme, matching `FilterResultsBar`.
    @ViewBuilder
    private var loginButton: some View {
        let enabled = auth.status != .signingIn
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
        let button = Button(action: submit) {
            HStack(spacing: 8) {
                if auth.status == .signingIn {
                    ProgressView()
                        .controlSize(.small)
                        .accentFill()
                    Text("Logging In…")
                } else {
                    Text("Log In")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!enabled)

        if enabled {
            button.buttonStyle(.kudosPrimaryConfirm)
        } else {
            button
                .buttonStyle(UndimmedButtonStyle())
                .font(.headline)
                .foregroundStyle(themeManager.appTheme.textColor)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(themeManager.effectiveTint.opacity(0.15), in: Capsule())
        }
    }

    /// Banner above the always-mounted WebView during the visible fallback.
    private var fallbackChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Using alternative login method…", systemImage: "safari")
                .font(.headline)
            Text(auth.fallbackMessage ?? "Complete login on AO3 below.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = auth.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(themeManager.appTheme.backgroundColor)
    }

    private func submit() {
        guard auth.status != .signingIn else { return }
        let submittedPassword = password
        Task {
            await auth.login(username: username, password: submittedPassword)
            // Keep the password on failure so a typo fix is one edit, not a retype.
            // Success clears via the isLoggedIn onChange (and dismisses the sheet).
            if auth.isLoggedIn {
                password = ""
            }
        }
    }

    /// Opens an AO3 help page (sign-up / password reset) in the in-app Browse tab,
    /// dismissing the login sheet first. Login resumes when the user returns and
    /// signs in. AO3 uses Devise, so these are its standard registration / reset
    /// routes; either way AO3's own page shows the current invitation/reset flow.
    private func openOnAO3(_ url: URL) {
        userInitiatedClose = true
        auth.cancelLogin()
        dismiss()
        router.open(url)
    }
}
