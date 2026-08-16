import Foundation
import Testing
import WebKit
@testable import Kudos

/// M14 / WPA-2 / WPB-6: pin WP-A's broader allow-list at the production
/// functions, not just `persistableCookies`. A revert that re-widens the
/// persisted blob to every AO3-domain cookie, or that stops pruning on
/// `install` / `merging` / `capture`, must turn these red.
///
/// Allow-list: `AO3RequestDefaults.persistedCookieNames` =
/// `{ _otwarchive_session, user_credentials }`.
@MainActor
struct CookieAllowListTests {
    @Test func responseCookiesDropsOffDomainAndNonAllowListed() throws {
        let ao3 = try #require(URL(string: "https://archiveofourown.org/"))
        let setCookies = [
            "\(AO3RequestDefaults.sessionCookieName)=keep-sess; Path=/; Secure",
            "user_credentials=keep-rem; Path=/; Secure",
            "_ga=drop-ga; Path=/; Secure",
            "viewed_adult=drop-adult; Path=/; Secure"
        ]
        let raw = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": setCookies.joined(separator: ", ")],
            for: ao3
        )
        #expect(
            raw.contains { $0.name == "_ga" },
            "fixture never produced _ga — name-filter test proved nothing"
        )
        #expect(
            raw.contains { $0.name == AO3RequestDefaults.sessionCookieName },
            "fixture never produced the session cookie — test proved nothing"
        )
        #expect(
            raw.contains { $0.name == "user_credentials" },
            "fixture never produced user_credentials — test proved nothing"
        )

        let response = try httpResponse(url: ao3, setCookies: setCookies)
        let kept = LiveAO3SessionValidator.responseCookies(from: response, url: ao3)
        let names = Set(kept.map(\.name))
        #expect(
            names.contains(AO3RequestDefaults.sessionCookieName),
            "session cookie dropped from AO3 Set-Cookie"
        )
        #expect(
            names.contains("user_credentials"),
            "remember-me cookie dropped from AO3 Set-Cookie"
        )
        #expect(!names.contains("_ga"), "non-allow-listed _ga was kept from Set-Cookie")
        #expect(
            !names.contains("viewed_adult"),
            "non-allow-listed viewed_adult was kept from Set-Cookie"
        )
        #expect(names == [
            AO3RequestDefaults.sessionCookieName,
            "user_credentials"
        ])

        let evil = try #require(URL(string: "https://evil.example/"))
        let stolenFields = [
            "\(AO3RequestDefaults.sessionCookieName)=stolen; Path=/; Secure",
            "user_credentials=stolen-rem; Path=/; Secure"
        ]
        let stolenRaw = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": stolenFields.joined(separator: ", ")],
            for: evil
        )
        #expect(
            !stolenRaw.isEmpty,
            "fixture never produced off-domain cookies — domain-filter test proved nothing"
        )
        let stolen = try httpResponse(url: evil, setCookies: stolenFields)
        let offDomain = LiveAO3SessionValidator.responseCookies(from: stolen, url: evil)
        #expect(offDomain.isEmpty, "off-domain Set-Cookie was kept")
    }

    @Test func mergingDropsNonAllowListedAndOffDomainStoredCookies() {
        let stored = AO3Session(
            username: "reader",
            cookies: [
                AO3StoredCookie(
                    name: AO3RequestDefaults.sessionCookieName, value: "sess"
                ),
                AO3StoredCookie(name: "user_credentials", value: "rem"),
                AO3StoredCookie(name: "_ga", value: "decoy"),
                AO3StoredCookie(name: "viewed_adult", value: "true"),
                AO3StoredCookie(
                    name: AO3RequestDefaults.sessionCookieName,
                    value: "stolen",
                    domain: "evil.example"
                )
            ]
        )
        let merged = LiveAO3SessionValidator.merging([], into: stored, username: "reader")
        let names = Set(merged.cookies.map(\.name))
        #expect(names.contains(AO3RequestDefaults.sessionCookieName))
        #expect(names.contains("user_credentials"))
        #expect(!names.contains("_ga"), "non-allow-listed _ga survived merging")
        #expect(
            !names.contains("viewed_adult"),
            "non-allow-listed viewed_adult survived merging"
        )
        #expect(
            !merged.cookies.contains { $0.domain.contains("evil") },
            "off-domain session cookie survived merging"
        )
        #expect(merged.cookies.contains {
            $0.name == AO3RequestDefaults.sessionCookieName && $0.value == "sess"
        })
        #expect(Set(merged.cookies.map(\.name)) == [
            AO3RequestDefaults.sessionCookieName,
            "user_credentials"
        ])
    }

    /// Production entry: `AO3CookieBridge.install`. A legacy blob can still
    /// hold extra cookies; restore must not re-inject them into WebKit.
    @Test func installDoesNotReinjectNonAllowListedCookiesIntoWebKit() async throws {
        let marker = UUID().uuidString
        let sessionValue = "sess-\(marker)"
        let decoyValue = "ga-\(marker)"
        let adultValue = "adult-\(marker)"
        let session = AO3Session(
            username: "reader",
            cookies: [
                AO3StoredCookie(
                    name: AO3RequestDefaults.sessionCookieName, value: sessionValue
                ),
                AO3StoredCookie(name: "user_credentials", value: "rem-\(marker)"),
                AO3StoredCookie(name: "_ga", value: decoyValue),
                AO3StoredCookie(name: "viewed_adult", value: adultValue)
            ]
        )
        await AO3CookieBridge.install(session)
        let installed = await allCookies(in: WKWebsiteDataStore.default().httpCookieStore)
        #expect(
            installed.contains {
                $0.name == AO3RequestDefaults.sessionCookieName && $0.value == sessionValue
            },
            "allow-listed session cookie was not installed — test proved nothing"
        )
        #expect(
            !installed.contains { $0.name == "_ga" && $0.value == decoyValue },
            "non-allow-listed _ga was reinstalled into WebKit"
        )
        #expect(
            !installed.contains { $0.name == "viewed_adult" && $0.value == adultValue },
            "non-allow-listed viewed_adult was reinstalled into WebKit"
        )
        await AO3CookieBridge.clearAO3Cookies()
    }

    /// Production entry: `AO3CookieBridge.captureAO3Cookies`.
    @Test func captureDropsNonAllowListedCookiesFromWebKitStore() async throws {
        let marker = UUID().uuidString
        let sessionCookie = try #require(HTTPCookie(properties: [
            .domain: ".archiveofourown.org",
            .path: "/",
            .name: AO3RequestDefaults.sessionCookieName,
            .value: "cap-sess-\(marker)",
            .secure: "TRUE"
        ]))
        let remember = try #require(HTTPCookie(properties: [
            .domain: ".archiveofourown.org",
            .path: "/",
            .name: "user_credentials",
            .value: "cap-rem-\(marker)",
            .secure: "TRUE"
        ]))
        let decoy = try #require(HTTPCookie(properties: [
            .domain: ".archiveofourown.org",
            .path: "/",
            .name: "_ga",
            .value: "cap-ga-\(marker)",
            .secure: "TRUE"
        ]))
        let store = WKWebsiteDataStore.default().httpCookieStore
        await set(sessionCookie, in: store)
        await set(remember, in: store)
        await set(decoy, in: store)
        let seeded = await allCookies(in: store)
        #expect(
            seeded.contains { $0.name == "_ga" && $0.value == decoy.value },
            "decoy never landed in WebKit — capture test proved nothing"
        )
        #expect(seeded.contains {
            $0.name == AO3RequestDefaults.sessionCookieName
                && $0.value == sessionCookie.value
        })

        let captured = await AO3CookieBridge.captureAO3Cookies()
        let names = Set(captured.map(\.name))
        #expect(captured.contains {
            $0.name == AO3RequestDefaults.sessionCookieName
                && $0.value == sessionCookie.value
        })
        #expect(captured.contains {
            $0.name == "user_credentials" && $0.value == remember.value
        })
        #expect(
            !captured.contains { $0.name == "_ga" && $0.value == decoy.value },
            "capture re-widened to every AO3-domain cookie"
        )
        #expect(!names.contains("_ga"))
        #expect(!names.contains("viewed_adult"))

        await delete(sessionCookie, from: store)
        await delete(remember, from: store)
        await delete(decoy, from: store)
    }

    private func httpResponse(url: URL, setCookies: [String]) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": setCookies.joined(separator: ", ")]
        ))
    }

    private func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) { continuation.resume() }
        }
    }

    private func delete(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }
}
