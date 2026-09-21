import CoreText
import Foundation
import Testing
@testable import Kudos

/// A font must never be able to cost a reader their library.
///
/// Restore refuses the **entire** backup over a single font it will not accept
/// — `KudosBackupFontRestoreTests` pins that deliberately, because a font that
/// fails these checks is not distinguishable from a hostile payload. Font
/// installation, meanwhile, checked nothing at all: it read the file, wrote it,
/// and inserted the row. The picker's `.font` content type happily offers
/// `.ttc` and `.woff`, and no size was ever looked at.
///
/// So the app could accept a font, put it in every backup it wrote, and then
/// refuse to restore those backups — with the reader finding out on the new
/// phone, at the one moment the library had to come back. These tests pin the
/// shared rule that installation and export now apply up front.
struct CustomFontBackupCompatibilityTests {
    /// A genuine installed font, so "valid" means what the system font stack
    /// means by it rather than what a fixture asserts.
    private func realFont() throws -> (data: Data, ext: String) {
        let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        for name in names.sorted() {
            let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 12.0)
            guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
            else { continue }
            let ext = url.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" else { continue }
            guard let data = try? Data(contentsOf: url),
                  data.count <= KudosBackupContents.maxFontEntryBytes
            else { continue }
            return (data, ext)
        }
        throw KudosBackupError.invalidPackage
    }

    @Test func aRealInstalledFontIsAccepted() throws {
        let font = try realFont()
        #expect(
            KudosBackupContents.fontRejectionReason(
                fileName: "\(UUID().uuidString).\(font.ext)",
                data: font.data
            ) == nil
        )
    }

    /// The case that cost the library: a perfectly good font in a container the
    /// restore does not take. `.ttc` is ordinary on macOS and the import picker
    /// offers it, so this was reachable without doing anything unusual.
    @Test func aGoodFontInAnUnsupportedContainerIsRefused() throws {
        let font = try realFont()
        for ext in ["ttc", "woff", "woff2", "dfont", ""] {
            let name = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
            #expect(
                KudosBackupContents.fontRejectionReason(fileName: name, data: font.data) != nil,
                "\(ext.isEmpty ? "no extension" : ext) must not reach a backup"
            )
        }
    }

    @Test func aFontLargerThanABackupCanCarryIsRefused() {
        let oversized = Data(repeating: 0, count: KudosBackupContents.maxFontEntryBytes + 1)
        #expect(
            KudosBackupContents.fontRejectionReason(
                fileName: "\(UUID().uuidString).ttf", data: oversized
            ) != nil
        )
    }

    /// Restore runs the bytes through `CGFont` before accepting them, so
    /// anything that only looks like a font by its name is refused here too.
    @Test func bytesThatAreNotAFontAreRefused() {
        let notAFont = Data([0x00, 0x01, 0x00, 0x00]) + Data("not a font".utf8)
        #expect(
            KudosBackupContents.fontRejectionReason(
                fileName: "\(UUID().uuidString).ttf", data: notAFont
            ) != nil
        )
    }

    @Test func aPathInTheNameIsRefused() throws {
        let font = try realFont()
        for name in ["../escape.ttf", "nested/font.ttf"] {
            #expect(
                KudosBackupContents.fontRejectionReason(fileName: name, data: font.data) != nil,
                "\(name) must not reach a backup"
            )
        }
    }

    /// The reason is shown to the reader, so it has to say something.
    @Test func everyRefusalExplainsItself() {
        let reason = KudosBackupContents.fontRejectionReason(
            fileName: "\(UUID().uuidString).woff", data: Data([0x00])
        )
        let text = try? #require(reason)
        #expect(text?.isEmpty == false)
        #expect(text?.hasSuffix(".") == true)
    }
}
