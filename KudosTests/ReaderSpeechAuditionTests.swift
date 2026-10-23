#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import Kudos

/// I16, from A88c's iPhone shots of the Listening page (the reader's Read Aloud sheet shares it).
@MainActor
struct ReaderSpeechAuditionTests {
    private func height(of view: some View) -> CGFloat {
        let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, .accessibility5))
        // About what a form row leaves for its content on a 402 pt iPhone.
        renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
        renderer.scale = 1
        return renderer.uiImage?.size.height ?? 0
    }

    /// At AX5 the system picker cut "Plain Narration" to "Plain…rration"; the menu's label wraps.
    @Test func theSampleValueWrapsWholeAtTheLargestText() {
        let line = height(of: ReaderSpeechAuditionHarness.sampleMenuLabel("Plain"))
        let value = height(of: ReaderSpeechAuditionHarness.sampleMenuLabel(AuditionSample.narration.rawValue))
        #expect(line > 0)
        #expect(value > line * 1.5, "\"Plain Narration\" takes a second line instead of being cut")
    }

    /// The strongest contrast between the pill's fill and a pixel on its middle row: the text's,
    /// unless the text has all but vanished into the fill, as `.bordered`'s disabled look did.
    private func textContrast(of pill: some View, on theme: ReaderTheme) -> Double {
        let renderer = ImageRenderer(content: pill
            .padding(8)
            .background(theme.cardSurface)
            .environment(\.colorScheme, theme == .dark || theme == .oled ? .dark : .light))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return 0 }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        func color(atX x: Int) -> Color {
            let index = ((height / 2) * width + x) * 4
            return Color(red: Double(pixels[index]) / 255, green: Double(pixels[index + 1]) / 255,
                         blue: Double(pixels[index + 2]) / 255)
        }
        // 8 pt of ground (16 px), then the capsule: 10 px into it is fill, well before the centred text.
        let fill = color(atX: 26)
        return (26 ..< width - 26).map { color(atX: $0).contrastRatio(on: fill) }.max() ?? 0
    }

    /// The current rate is disabled. It read as near-white on pale glass in Light and Sepia.
    @Test func theCurrentRateReadsInEveryTheme() {
        let current = Button {} label: { Text("1.0x (default)").frame(width: 160) }
            .buttonStyle(RatePillStyle())
            .disabled(true)
        // The process's first ImageRenderer pass can time out and draw nothing (contrast 1.0); warm it up.
        _ = textContrast(of: current, on: .light)
        for theme in ReaderTheme.allCases {
            #expect(textContrast(of: current, on: theme) >= 4.5, "\(theme)")
        }
    }

    /// `shot:pronunciations` at AX5 stopped on Listening: the push was taken by the Read Aloud
    /// section, which the form builds only once it scrolls into view. The page takes it now.
    @Test func thePronunciationsShotLeavesListeningAtTheLargestText() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "KudosDebugRoute")
        defaults.set("shot:pronunciations", forKey: "KudosDebugRoute")
        defer { defaults.set(previous, forKey: "KudosDebugRoute") }
        try #require(DebugLaunchRoute.wantsPush("pronunciations"))

        let host = UIHostingController(rootView: NavigationStack { SettingsListeningPage() }
            .environment(ThemeManager())
            .environment(\.dynamicTypeSize, .accessibility5))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        for _ in 0 ..< 40 where DebugLaunchRoute.wantsPush("pronunciations") {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!DebugLaunchRoute.wantsPush("pronunciations"), "the page took the push")
    }
}
#endif
