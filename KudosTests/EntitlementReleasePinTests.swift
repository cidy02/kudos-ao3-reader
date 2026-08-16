#if os(macOS)
import Foundation
import Testing

/// Production-entry assertions for the macOS Release signing pin.
///
/// These tests read the real `project.pbxproj` and `Kudos.entitlements` —
/// the files Xcode uses for a Release build — and invoke
/// `Scripts/check-macos-release-entitlements.sh`, which is the gate CI
/// and `Scripts/verify.sh` run. They are macOS-only because they must
/// see the host checkout and execute the guard script.
@Suite("Entitlement Release Pin")
struct EntitlementReleasePinTests {
    @Test func injectBaseAndEntitlementsPinAreMacOSQualified() throws {
        let block = try Self.appTargetReleaseBlock()
        #expect(
            block.contains(
                "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = \"kudos-ao3-reader/Kudos.entitlements\";"
            ),
            "Release CODE_SIGN_ENTITLEMENTS must be sdk=macosx* qualified so iOS keeps Keychain entitlements"
        )
        #expect(
            !block.contains("CODE_SIGN_ENTITLEMENTS = "),
            "Unqualified CODE_SIGN_ENTITLEMENTS on the five-platform Release target drops iOS Keychain"
        )
        #expect(
            block.contains("\"CODE_SIGN_INJECT_BASE_ENTITLEMENTS[sdk=macosx*]\" = NO;"),
            "Release CODE_SIGN_INJECT_BASE_ENTITLEMENTS must be sdk=macosx* qualified"
        )
        #expect(
            !block.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = "),
            "Unqualified CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO makes iOS Release fall back to the plaintext file vault"
        )
    }

    @Test func kudosEntitlementsCoverFolderSyncAndExcludeDebugger() throws {
        let data = try Data(contentsOf: Self.entitlementsURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(
            plist as? [String: Any],
            "Kudos.entitlements is not a dictionary"
        )

        func flag(_ key: String) -> Bool { dict[key] as? Bool == true }

        #expect(
            flag("com.apple.security.app-sandbox"),
            "Kudos.entitlements must enable app-sandbox"
        )
        #expect(
            flag("com.apple.security.network.client"),
            "Kudos.entitlements must allow outbound network"
        )
        #expect(
            flag("com.apple.security.files.user-selected.read-write"),
            "folder sync writes the user-selected Library Sync Folder"
        )
        #expect(
            flag("com.apple.security.files.bookmarks.app-scope"),
            "folder sync persists a security-scoped bookmark"
        )
        #expect(
            dict["com.apple.security.get-task-allow"] == nil,
            "Release entitlements must not declare get-task-allow"
        )
        #expect(
            dict["com.apple.security.files.user-selected.read-only"] == nil,
            "read-only is insufficient for folder sync writes"
        )
        for banned in [
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.cs.allow-unsigned-executable-memory",
            "com.apple.security.cs.allow-jit",
            "com.apple.security.cs.disable-executable-page-protection"
        ] {
            #expect(dict[banned] == nil, "\(banned) defeats ENABLE_HARDENED_RUNTIME")
        }
    }

    @Test func releaseConfigKeepsHardenedRuntimeAndRejectsAdHocIdentity() throws {
        let block = try Self.appTargetReleaseBlock()
        #expect(
            block.contains("ENABLE_HARDENED_RUNTIME = YES;"),
            "Release is missing ENABLE_HARDENED_RUNTIME = YES"
        )
        // Narrower than `contains("= NO")` — that would also fire on
        // INJECT_BASE = NO, which is required.
        let hrNo = block.range(
            of: #"ENABLE_HARDENED_RUNTIME.*= *NO;"#,
            options: .regularExpression
        )
        #expect(
            hrNo == nil,
            "Release has an ENABLE_HARDENED_RUNTIME override set to NO"
        )
        let adHoc = block.range(
            of: #"CODE_SIGN_IDENTITY.*= *"?-"?;"#,
            options: .regularExpression
        )
        #expect(adHoc == nil, "Release sets a CODE_SIGN_IDENTITY of \"-\" (ad-hoc)")
        #expect(
            block.contains("ENABLE_USER_SELECTED_FILES = readwrite;"),
            "Release ENABLE_USER_SELECTED_FILES must be readwrite for folder sync writes"
        )
        #expect(
            !block.contains("ENABLE_USER_SELECTED_FILES = readonly;"),
            "Release ENABLE_USER_SELECTED_FILES = readonly cannot write the Library Sync Folder"
        )
    }

    @Test func checkMacOSReleaseEntitlementsScriptAcceptsThisTree() throws {
        let script = Self.repoRoot.appendingPathComponent(
            "Scripts/check-macos-release-entitlements.sh"
        )
        #expect(FileManager.default.isExecutableFile(atPath: script.path))

        let process = Process()
        process.executableURL = script
        process.currentDirectoryURL = Self.repoRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        #expect(
            process.terminationStatus == 0,
            "check-macos-release-entitlements.sh exited \(process.terminationStatus): \(output)"
        )
        #expect(
            output.contains("check-macos-release-entitlements: OK"),
            "guard script did not print OK: \(output)"
        )
    }

    // MARK: - production files

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var entitlementsURL: URL {
        repoRoot.appendingPathComponent("kudos-ao3-reader/Kudos.entitlements")
    }

    private static func appTargetReleaseBlock() throws -> String {
        let url = repoRoot.appendingPathComponent(
            "AO3_App_OpenSource.xcodeproj/project.pbxproj"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let startNeedle = "Release configuration for PBXNativeTarget \"AO3_App_OpenSource\""
        guard let start = text.range(of: startNeedle) else {
            Issue.record("missing app-target Release block in project.pbxproj")
            return ""
        }
        let tail = text[start.lowerBound...]
        guard let end = tail.range(of: "name = Release;") else {
            Issue.record("app-target Release block has no terminator")
            return ""
        }
        return String(tail[..<end.upperBound])
    }
}
#endif
