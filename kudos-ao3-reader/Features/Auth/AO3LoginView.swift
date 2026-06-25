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

    private static let signUpURL = URL(string: "https://archiveofourown.org/users/new")!
    private static let passwordResetURL = URL(string: "https://archiveofourown.org/users/password/new")!

    var body: some View {
        NavigationStack {
            ZStack {
                // Keep the automatic-login WebView mounted (but invisible) during the
                // native phase so it has a window: an off-screen WKWebView can have its
                // web-content process throttled or suspended, which would make the
                // hidden login time out and drop to the fallback for no real reason.
                // When the fallback takes over it shows the same WebView full-size.
                if !auth.isUsingFallback {
                    WebView(webView: auth.loginWebView)
                        .frame(width: 1, height: 1)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if auth.isUsingFallback {
                    fallbackContent
                } else {
                    nativeContent
                }
            }
            .navigationTitle("Log In to AO3")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        auth.cancelLogin()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 440)
        .presentationDragIndicator(.visible)
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
            if !auth.isLoggedIn {
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

    private var fallbackContent: some View {
        VStack(spacing: 0) {
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

            Divider()
            WebView(webView: auth.loginWebView)
        }
        .background(themeManager.appTheme.backgroundColor)
    }

    private func submit() {
        guard auth.status != .signingIn else { return }
        Task {
            await auth.login(username: username, password: password)
            password = ""
        }
    }

    /// Opens an AO3 help page (sign-up / password reset) in the in-app Browse tab,
    /// dismissing the login sheet first. Login resumes when the user returns and
    /// signs in. AO3 uses Devise, so these are its standard registration / reset
    /// routes; either way AO3's own page shows the current invitation/reset flow.
    private func openOnAO3(_ url: URL) {
        dismiss()
        router.open(url)
    }
}
