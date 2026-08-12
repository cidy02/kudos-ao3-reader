import Foundation
import SwiftSoup
import Testing
import WebKit
@testable import Kudos

/// Additional adversarial cases for the independent Grok security audit.
/// Artifacts are also written under `audit-artifacts/` when that directory exists
/// next to the repo root; tests never contact archiveofourown.org.
struct SecurityAuditAdversarialTests {
    private let sentinel = "SYNTHETIC_TEST_SESSION_0001"

    private func freshTempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kudos-audit-\(UUID().uuidString)")
    }

    private func writeArtifact(_ name: String, data: Data) {
        let repoArtifacts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("audit-artifacts", isDirectory: true)
        guard FileManager.default.fileExists(atPath: repoArtifacts.path)
                || ((try? FileManager.default.createDirectory(
                    at: repoArtifacts, withIntermediateDirectories: true
                )) != nil)
        else { return }
        try? data.write(to: repoArtifacts.appendingPathComponent(name))
    }

    // MARK: - MiniZip extra hostile names

    @Test func deflateEntryWithZeroCompressedSizeBypassesRatioCheck() throws {
        // Method 8 + compressedSize 0 skips the ratio guard (MiniZip.swift
        // validateMethodAndSize). A 2 MiB declared output is well under the
        // 200 MiB EPUB cap, so construction succeeds and inflate still
        // allocates `expectedSize` bytes.
        let archive = HostileZipFixture.build([
            HostileZipFixture.Entry(
                name: "bomb.bin",
                method: 8,
                payload: Data(),
                declaredCompressedSize: 0,
                declaredUncompressedSize: 2_000_000
            )
        ])
        writeArtifact("zero-compressed-size-bomb.zip", data: archive)
        let zip = try MiniZip(data: archive)
        #expect(zip.names.contains("bomb.bin"))
        _ = zip.data(named: "bomb.bin")
    }

    @Test func unicodeDotDotAndNullAndFileSchemeAreRejected() {
        let cases = [
            "../evil.txt",
            "foo/../../etc/passwd",
            "foo//bar.txt",
            "file://etc/passwd",
            "foo\0bar.txt",
            "/absolute.txt",
            "C:\\Windows\\win.ini"
        ]
        for name in cases {
            let archive = HostileZipFixture.build([
                HostileZipFixture.Entry(name: name, payload: Data("hostile".utf8))
            ])
            #expect(throws: MiniZipError.self, "expected rejection for \(name)") {
                _ = try MiniZip(data: archive)
            }
        }
    }

    @Test func fullwidthSlashDoesNotEscapeExtractionRoot() throws {
        // U+FF0F fullwidth solidus is not a path separator. The archive is
        // allowed; extraction must still stay inside the staging root.
        let name = "..／evil.txt"
        let archive = HostileZipFixture.build([
            HostileZipFixture.Entry(name: name, payload: Data("hostile".utf8))
        ])
        writeArtifact("fullwidth-slash.zip", data: archive)
        let zip = try MiniZip(data: archive)
        let dest = freshTempDir()
        defer { try? FileManager.default.removeItem(at: dest) }
        try zip.unzip(to: dest)
        let extracted = dest.appendingPathComponent(name)
        #expect(FileManager.default.fileExists(atPath: extracted.path))
        #expect(extracted.standardizedFileURL.path.hasPrefix(dest.standardizedFileURL.path))
    }

    @Test func caseFoldingDuplicateNamesAreDistinctToMiniZip() throws {
        let archive = HostileZipFixture.build([
            HostileZipFixture.Entry(name: "Works/A.epub", payload: Data("upper".utf8)),
            HostileZipFixture.Entry(name: "works/A.epub", payload: Data("lower".utf8))
        ])
        writeArtifact("case-fold-collision.zip", data: archive)
        let zip = try MiniZip(data: archive)
        #expect(zip.data(named: "Works/A.epub") == Data("upper".utf8))
        #expect(zip.data(named: "works/A.epub") == Data("lower".utf8))
    }

    // MARK: - Backup materialization

    @Test func backupInitMaterializesEveryReferencedEPUBInMemory() throws {
        let workIDs = (0 ..< 4).map { _ in UUID() }
        let payload = Data(repeating: 0x41, count: 256 * 1024)
        var entries: [(name: String, data: Data)] = [(
            name: "manifest.json",
            data: Data("""
            {
              "version": 8,
              "exportedAt": "2026-01-01T00:00:00.000Z",
              "works": [
                \(workIDs.map { "{\"id\":\"\($0.uuidString)\",\"title\":\"t\",\"author\":\"a\",\"summary\":\"\",\"sourceURL\":\"\",\"dateAdded\":\"2026-01-01T00:00:00.000Z\",\"isFavorite\":false,\"isSaved\":true,\"isFinished\":false,\"hasEPUB\":true,\"isComplete\":false,\"rating\":\"\",\"language\":\"\",\"wordCount\":0,\"chapters\":\"\",\"kudos\":0,\"comments\":0,\"bookmarks\":0,\"hits\":0,\"workWarnings\":[],\"workCategories\":[],\"seriesTitle\":\"\",\"seriesPosition\":0,\"seriesURL\":\"\",\"lastSpineIndex\":0,\"lastScrollFraction\":0,\"workTags\":[],\"workFandoms\":[],\"workCharacters\":[],\"workRelationships\":[],\"workFreeforms\":[],\"workTagsFetched\":false,\"ao3Unavailable\":false,\"isQueuedForLater\":false,\"epubPreservationStatusRaw\":\"none\",\"metadataSyncStatusRaw\":\"idle\"}" }.joined(separator: ",\n"))
              ],
              "bookmarks": [],
              "fonts": [],
              "settings": {
                "readerFontID": "system",
                "readerMode": "scroll",
                "readerTwoPage": false,
                "readerCustomize": false,
                "readerBoldText": false,
                "readerFontPt": 18,
                "readerLineHeight": 1.65,
                "readerLetterSpacing": 0,
                "readerWordSpacing": 0,
                "readerMargin": 28,
                "readerJustify": false,
                "confirmBeforeDelete": true,
                "hideMatureContent": false,
                "matureContentMode": "obscure",
                "requireBiometricToReveal": false,
                "appTheme": "light",
                "readerTheme": "light",
                "matchAppReaderTheme": true,
                "accentColorHex": "#990000",
                "autoPreserveSmallSeriesOnSaveForLater": false,
                "autoPreserveSeriesWorkThreshold": 5
              }
            }
            """.utf8)
        )]
        for id in workIDs {
            entries.append((name: "Works/\(id.uuidString).epub", data: payload))
        }
        let archive = try MiniZip.archiveData(entries)
        writeArtifact("in-memory-materialization.kudosbackup", data: archive)
        let contents = try KudosBackupContents(zipData: archive)
        #expect(contents.epubFiles.count == workIDs.count)
        let total = contents.epubFiles.values.reduce(0) { $0 + $1.count }
        #expect(total == payload.count * workIDs.count)
        #expect(contents.manifest.settings.hideMatureContent == false)
        #expect(contents.manifest.settings.requireBiometricToReveal == false)
    }

    @Test func backupRestoreAppliesPrivacySettingsFromArchive() throws {
        let defaults = UserDefaults(suiteName: "kudos-audit-\(UUID().uuidString)")!
        defaults.set(true, forKey: "hideMatureContent")
        defaults.set(true, forKey: "requireBiometricToReveal")
        let settings = try KudosBackupContents.decodeManifest(Data("""
        {
          "version": 8,
          "exportedAt": "2026-01-01T00:00:00.000Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "settings": {
            "readerFontID": "system",
            "readerMode": "scroll",
            "readerTwoPage": false,
            "readerCustomize": false,
            "readerBoldText": false,
            "readerFontPt": 18,
            "readerLineHeight": 1.65,
            "readerLetterSpacing": 0,
            "readerWordSpacing": 0,
            "readerMargin": 28,
            "readerJustify": false,
            "confirmBeforeDelete": true,
            "hideMatureContent": false,
            "matureContentMode": "show",
            "requireBiometricToReveal": false,
            "appTheme": "light",
            "readerTheme": "light",
            "matchAppReaderTheme": true,
            "accentColorHex": "#990000",
            "autoPreserveSmallSeriesOnSaveForLater": false,
            "autoPreserveSeriesWorkThreshold": 5
          }
        }
        """.utf8)).settings
        settings.apply(to: defaults)
        #expect(defaults.bool(forKey: "hideMatureContent") == false)
        #expect(defaults.bool(forKey: "requireBiometricToReveal") == false)
    }

    // MARK: - Cookie / URL policy

    @Test func trustedURLRejectsLookalikesAndCleartext() throws {
        #expect(AO3RequestDefaults.isTrustedURL(URL(string: "https://archiveofourown.org/works/1")))
        #expect(AO3RequestDefaults.isTrustedURL(URL(string: "https://download.archiveofourown.org/x")))
        #expect(!AO3RequestDefaults.isTrustedURL(URL(string: "https://fake-archiveofourown.org")))
        #expect(!AO3RequestDefaults.isTrustedURL(URL(string: "https://archiveofourown.org.evil.com")))
        #expect(!AO3RequestDefaults.isTrustedURL(URL(string: "http://archiveofourown.org")))
        #expect(!AO3RequestDefaults.isTrustedURL(URL(string: "https://example.com")))
        #expect(!AO3RequestDefaults.isTrustedURL(URL(string: "file:///tmp")))
    }

    @Test func storedCookieDoesNotApplyToForeignHostsOrHTTP() throws {
        let cookie = AO3StoredCookie(
            name: AO3RequestDefaults.sessionCookieName,
            value: sentinel,
            domain: ".archiveofourown.org",
            path: "/",
            isSecure: true,
            isHTTPOnly: true
        )
        #expect(cookie.applies(to: URL(string: "https://archiveofourown.org/")!))
        #expect(cookie.applies(to: URL(string: "https://www.archiveofourown.org/")!))
        #expect(!cookie.applies(to: URL(string: "https://evil.com/")!))
        #expect(!cookie.applies(to: URL(string: "https://notarchiveofourown.org/")!))
        #expect(!cookie.applies(to: URL(string: "http://archiveofourown.org/")!))
        #expect(cookie.httpCookie?.isSecure == true)
    }

    @Test func storedCookieSerializationDropsSameSite() throws {
        let cookie = AO3StoredCookie(name: "_otwarchive_session", value: sentinel)
        let data = try JSONEncoder().encode(cookie)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.lowercased().contains("samesite"))
        #expect(json.contains(sentinel))
    }

    @Test func fileVaultPersistsSentinelInClearJSON() throws {
        let url = freshTempDir().appendingPathComponent("ao3-session.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vault = FileAO3SessionVault(fileURL: url)
        try vault.save(AO3Session(
            username: "audit-user",
            cookies: [AO3StoredCookie(name: AO3RequestDefaults.sessionCookieName, value: sentinel)]
        ))
        let raw = try String(contentsOf: url, encoding: .utf8)
        writeArtifact("file-vault-session.json", data: Data(raw.utf8))
        #expect(raw.contains(sentinel))
        #expect(raw.contains("_otwarchive_session"))
        try vault.delete()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func redirectRelayStripsCookieOffAO3() throws {
        let action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader: "_otwarchive_session=\(sentinel)",
            responseHeaderFields: [:],
            responseURL: URL(string: "https://archiveofourown.org/login"),
            newRequestURL: URL(string: "https://evil.example/steal")
        )
        #expect(action == .strip)
    }

    @Test func commentAvatarResolverAcceptsAbsoluteForeignHosts() throws {
        let foreign = AO3Comment.avatarURL(forIconSource: "https://evil.example/pixel.png")
        #expect(foreign?.host == "evil.example")
        let relative = AO3Comment.avatarURL(forIconSource: "/images/skins/iconsets/default/icon_user.png")
        #expect(relative == nil)
    }

    @Test func writeAbsoluteURLDoesNotHostCheckAbsoluteHTTP() {
        let url = AO3AuthService.absoluteURL("https://evil.example/steal")
        #expect(url?.host == "evil.example")
    }

    @Test func htmlSanitizerStripsScriptAndImages() throws {
        let dirty = """
        <p>hello<script>document.cookie</script><img src="https://evil.example/x"><a href="https://example.com">x</a></p>
        """
        let fragment = try HTMLWorkSanitizer.fragment(ofAll: [
            try SwiftSoup.parseBodyFragment(dirty).body()!
        ])
        #expect(!fragment.lowercased().contains("<script"))
        #expect(!fragment.lowercased().contains("<img"))
        #expect(fragment.contains("hello"))
    }

    // MARK: - WebKit origin isolation (no AO3 network)

    @MainActor
    @Test func fileOriginCannotReadAO3DomainCookieFromDefaultStore() async throws {
        let store = WKWebsiteDataStore.default()
        let cookie = try #require(HTTPCookie(properties: [
            .name: AO3RequestDefaults.sessionCookieName,
            .value: sentinel,
            .domain: ".archiveofourown.org",
            .path: "/",
            .secure: "TRUE",
            HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE"
        ]))
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.httpCookieStore.setCookie(cookie) { cont.resume() }
        }
        defer {
            store.httpCookieStore.delete(cookie)
        }

        let dir = freshTempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = """
        <html><body><script>
        window.webkit.messageHandlers.probe.postMessage(document.cookie || "");
        </script></body></html>
        """
        let file = dir.appendingPathComponent("probe.html")
        try html.write(to: file, atomically: true, encoding: .utf8)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        let probe = CookieProbe()
        config.userContentController.add(probe, name: "probe")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), configuration: config)
        _ = web
        web.loadFileURL(file, allowingReadAccessTo: dir)
        let seen = await probe.nextMessage(timeout: 5)
        #expect(seen != nil, "probe script should post document.cookie")
        #expect(!(seen ?? "").contains(sentinel), "file:// must not see the AO3 session cookie")
        config.userContentController.removeScriptMessageHandler(forName: "probe")
    }
}

@MainActor
private final class CookieProbe: NSObject, WKScriptMessageHandler {
    private var continuation: CheckedContinuation<String?, Never>?

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        continuation?.resume(returning: message.body as? String)
        continuation = nil
    }

    func nextMessage(timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { cont in
            continuation = cont
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let continuation {
                    self.continuation = nil
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
