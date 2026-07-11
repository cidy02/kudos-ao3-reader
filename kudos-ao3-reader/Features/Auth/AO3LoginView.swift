import SwiftUI

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

    private static let signUpURL = URL(string: "https://archiveofourown.org/users/new")!
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        userInitiatedClose = true
                        auth.cancelLogin()
                        dismiss()
                    }
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
        Form {
            Group {
                Section {
                    TextField("Username or email", text: $username)
                        .textContentType(.username)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                        .submitLabel(.next)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                } header: {
                    Label("AO3 Account", systemImage: "person.crop.circle")
                } footer: {
                    Text("Kudos submits these credentials only to AO3's official login page. "
                        + "Your password is never saved.")
                }

                if let error = auth.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if auth.status == .signingIn {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Logging In…")
                            } else {
                                Label("Log In", systemImage: "person.badge.key")
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        auth.status == .signingIn
                            || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || password.isEmpty
                    )
                }

                Section {
                    Button {
                        openOnAO3(Self.signUpURL)
                    } label: {
                        Label("Create an AO3 account", systemImage: "person.badge.plus")
                    }
                    Button {
                        openOnAO3(Self.passwordResetURL)
                    } label: {
                        Label("Forgot your password?", systemImage: "key")
                    }
                } footer: {
                    Text("These open AO3 in the Browse tab. Come back here to log in afterwards.")
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
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
