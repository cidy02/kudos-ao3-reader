import Foundation
import WebKit

enum AO3WebLoginError: LocalizedError, Equatable {
    case invalidCredentials(String)
    case fallbackRequired(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials(let message), .fallbackRequired(let message):
            message
        }
    }
}

/// The small, testable snapshot returned by JavaScript after each AO3 navigation.
/// A session cookie alone is not proof of authentication because AO3 also gives
/// logged-out visitors an anonymous `_otwarchive_session` cookie.
struct AO3LoginPageObservation: Equatable, Sendable {
    let isLoggedIn: Bool
    let username: String?
    let errorMessage: String?
    let hasLoginForm: Bool

    init(isLoggedIn: Bool, username: String?, errorMessage: String?, hasLoginForm: Bool) {
        self.isLoggedIn = isLoggedIn
        self.username = username?.nilIfBlank
        self.errorMessage = errorMessage?.nilIfBlank
        self.hasLoginForm = hasLoginForm
    }

    init(javaScriptValue: Any?) {
        let values = javaScriptValue as? [String: Any]
        self.init(
            isLoggedIn: values?["isLoggedIn"] as? Bool ?? false,
            username: values?["username"] as? String,
            errorMessage: values?["errorMessage"] as? String,
            hasLoginForm: values?["hasLoginForm"] as? Bool ?? false
        )
    }
}

@MainActor
protocol AO3LoginPerforming: AnyObject {
    var webView: WKWebView { get }

    func login(username: String, password: String) async throws -> AO3Session
    func beginManualLogin(
        expectedUsername: String,
        onAuthenticated: @escaping (AO3Session) -> Void,
        onError: @escaping (String) -> Void
    )
    func applyVisibleTheme(_ theme: ReaderTheme)
    func cancel()
}

/// Drives AO3's real login form in a WKWebView. Normal login is entirely hidden:
/// load `/users/login`, let AO3 generate the CSRF field, fill the official form,
/// and submit it. If that mechanism breaks, the same WebView is handed to the
/// visible fallback so challenges or changed forms can be completed manually.
@MainActor
final class AO3WebLoginCoordinator: NSObject, AO3LoginPerforming {
    let webView: WKWebView

    private enum Phase: Equatable {
        case idle
        case loadingLogin
        case submitting
        case manual
    }

    private static let loginURL = URL(string: "https://archiveofourown.org/users/login")!
    private static let timeout: Duration = .seconds(25)

    private var phase: Phase = .idle
    private var pendingCredentials: (username: String, password: String)?
    private var hiddenExpectedUsername = ""
    private var hiddenContinuation: CheckedContinuation<AO3Session, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var manualExpectedUsername = ""
    private var onManualAuthenticated: ((AO3Session) -> Void)?
    private var onManualError: ((String) -> Void)?
    private var visibleTheme: ReaderTheme = .light

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        #if os(iOS)
        webView.isOpaque = false
        #endif
    }

    func login(username: String, password: String) async throws -> AO3Session {
        cancel()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                hiddenContinuation = continuation
                pendingCredentials = (username, password)
                hiddenExpectedUsername = username
                phase = .loadingLogin
                webView.load(URLRequest(url: Self.loginURL))
                startTimeout()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func beginManualLogin(
        expectedUsername: String,
        onAuthenticated: @escaping (AO3Session) -> Void,
        onError: @escaping (String) -> Void
    ) {
        timeoutTask?.cancel()
        pendingCredentials = nil
        hiddenExpectedUsername = ""
        manualExpectedUsername = expectedUsername
        onManualAuthenticated = onAuthenticated
        onManualError = onError
        phase = .manual

        guard BrowserThemeStyle.isAO3URL(webView.url) else {
            webView.load(URLRequest(url: Self.loginURL))
            return
        }
        inspectManualPage()
    }

    func applyVisibleTheme(_ theme: ReaderTheme) {
        visibleTheme = theme
        guard phase == .manual else { return }
        applyThemeScript()
    }

    func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingCredentials = nil
        hiddenExpectedUsername = ""
        webView.stopLoading()
        if let hiddenContinuation {
            self.hiddenContinuation = nil
            hiddenContinuation.resume(throwing: CancellationError())
        }
        onManualAuthenticated = nil
        onManualError = nil
        manualExpectedUsername = ""
        phase = .idle
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.failHidden(
                .fallbackRequired("The automatic AO3 login timed out.")
            )
        }
    }

    private func handleFinishedNavigation() async {
        guard AO3RequestDefaults.isTrustedURL(webView.url) else {
            handleUntrustedNavigation()
            return
        }

        do {
            let observation = try await inspectPage()
            if observation.isLoggedIn {
                await completeAuthentication(
                    username: observation.username ?? expectedUsername
                )
                return
            }

            switch phase {
            case .loadingLogin:
                guard observation.hasLoginForm, let credentials = pendingCredentials else {
                    failHidden(.fallbackRequired(
                        "AO3's login form could not be recognized."
                    ))
                    return
                }
                phase = .submitting
                pendingCredentials = nil
                let submitted = try await submit(credentials)
                if !submitted {
                    failHidden(.fallbackRequired(
                        "AO3's login form could not be submitted automatically."
                    ))
                }

            case .submitting:
                if let message = observation.errorMessage {
                    failHidden(.invalidCredentials(message))
                } else {
                    failHidden(.fallbackRequired(
                        "AO3 did not confirm the automatic login."
                    ))
                }

            case .manual:
                applyThemeScript()

            case .idle:
                break
            }
        } catch {
            switch phase {
            case .manual:
                onManualError?("The AO3 login page could not be checked.")
            case .loadingLogin, .submitting:
                failHidden(.fallbackRequired(
                    "The automatic AO3 login could not inspect the page."
                ))
            case .idle:
                break
            }
        }
    }

    private func handleUntrustedNavigation() {
        switch phase {
        case .manual:
            onManualError?("Return to AO3 to complete login.")
        case .loadingLogin, .submitting:
            failHidden(.fallbackRequired(
                "AO3 redirected the automatic login away from its secure site."
            ))
        case .idle:
            break
        }
    }

    private func inspectManualPage() {
        Task { [weak self] in
            guard let self else { return }
            await self.handleFinishedNavigation()
        }
    }

    private func completeAuthentication(username: String) async {
        let cookies = await AO3CookieBridge.captureAO3Cookies()
        let session = AO3Session(username: username, cookies: cookies)
        guard session.hasSessionCookie else {
            if phase == .manual {
                onManualError?("AO3 logged in, but its session cookie could not be captured.")
            } else {
                failHidden(.fallbackRequired(
                    "AO3 logged in, but its session cookie could not be captured."
                ))
            }
            return
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        hiddenExpectedUsername = ""
        if phase == .manual {
            let completion = onManualAuthenticated
            onManualAuthenticated = nil
            onManualError = nil
            phase = .idle
            completion?(session)
        } else if let hiddenContinuation {
            self.hiddenContinuation = nil
            phase = .idle
            hiddenContinuation.resume(returning: session)
        }
    }

    private func failHidden(_ error: AO3WebLoginError) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingCredentials = nil
        phase = .idle
        guard let hiddenContinuation else { return }
        self.hiddenContinuation = nil
        hiddenContinuation.resume(throwing: error)
    }

    private var expectedUsername: String {
        switch phase {
        case .manual: manualExpectedUsername
        default: hiddenExpectedUsername
        }
    }

    private func submit(_ credentials: (username: String, password: String)) async throws -> Bool {
        let username = Self.javaScriptLiteral(credentials.username)
        let password = Self.javaScriptLiteral(credentials.password)
        let script = """
        (function() {
          const form = document.querySelector('form#new_user');
          const login = document.querySelector('#user_login');
          const password = document.querySelector('#user_password');
          const remember = document.querySelector('#user_remember_me');
          if (!form || !login || !password) return false;
          login.value = \(username);
          password.value = \(password);
          if (remember) remember.checked = true;
          setTimeout(function() {
            if (form.requestSubmit) form.requestSubmit();
            else form.submit();
          }, 0);
          return true;
        })();
        """
        return try await evaluateBool(script)
    }

    private func inspectPage() async throws -> AO3LoginPageObservation {
        let script = """
        (function() {
          const logout = document.querySelector(
            'a[href="/users/logout"], form[action="/users/logout"]'
          );
          const isLoggedIn = !!logout ||
            !!(document.body && document.body.classList.contains('logged-in'));
          let username = null;
          const links = document.querySelectorAll('#greeting a[href^="/users/"]');
          for (const link of links) {
            const path = new URL(link.href, document.baseURI).pathname;
            const match = path.match(/^\\/users\\/([^/]+)$/);
            if (match && match[1] !== 'login' && match[1] !== 'logout') {
              username = decodeURIComponent(match[1]);
              break;
            }
          }
          const error = document.querySelector(
            '#main .flash.error, #main .error, .flash.error, .flash.alert'
          );
          return {
            isLoggedIn: isLoggedIn,
            username: username,
            errorMessage: error ? error.textContent.trim() : null,
            hasLoginForm: !!document.querySelector(
              'form#new_user #user_login, form#new_user input[name="user[login]"]'
            )
          };
        })();
        """
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: AO3LoginPageObservation(javaScriptValue: value))
                }
            }
        }
    }

    private func evaluateBool(_ script: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? Bool ?? false)
                }
            }
        }
    }

    private func applyThemeScript() {
        let script = BrowserThemeStyle.injectionScript(for: visibleTheme, url: webView.url)
        webView.evaluateJavaScript(script)
    }

    private static func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return literal
    }
}

extension AO3WebLoginCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            guard let self else { return }
            await self.handleFinishedNavigation()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure()
    }

    private func handleNavigationFailure() {
        switch phase {
        case .manual:
            onManualError?("AO3 could not load. Check your connection and try again.")
        case .loadingLogin, .submitting:
            failHidden(.fallbackRequired(
                "The automatic AO3 login could not load the page."
            ))
        case .idle:
            break
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
