#if os(iOS)
import SwiftUI
import ReadiumShared
import ReadiumNavigator

/// Phase-0 POC view model. Owns the Readium `Publication` and its
/// `EPUBNavigatorViewController`, mirrors a handful of reading settings, and
/// acts as the navigator's delegate (progress + taps). Deliberately isolated
/// from the production reader so the experiment can be deleted cleanly.
@Observable
@MainActor
final class ReadiumReaderModel: NSObject, EPUBNavigatorDelegate {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var title = ""
    /// Flat table of contents (falls back to the reading order / spine).
    /// `Link` is qualified because SwiftUI also defines a `Link` view.
    private(set) var toc: [ReadiumShared.Link] = []
    /// Latest reading position reported by the navigator (drives the progress UI).
    private(set) var currentLocator: Locator?
    /// Toggled by tapping the page; the POC view hides/show its chrome on this.
    var chromeHidden = false

    /// The hosted navigator, exposed so the container view can embed it.
    private(set) var navigator: EPUBNavigatorViewController?

    // Mirrored reading settings. Changing any of these re-submits preferences.
    var scroll = true { didSet { applyPreferences() } }
    var theme: ReadiumNavigator.Theme = .light { didSet { applyPreferences() } }
    var fontSize: Double = 1.0 { didSet { applyPreferences() } }

    /// Fraction through the whole publication (0...1), if the navigator knows it.
    var totalProgression: Double? { currentLocator?.locations.totalProgression }

    // MARK: Loading

    /// Imports the picked EPUB into the app sandbox, opens it as a Publication,
    /// and builds the navigator. Copying first means the navigator keeps file
    /// access while paging (a security-scoped picker URL would expire).
    func load(pickedURL: URL) async {
        phase = .loading
        do {
            let localURL = try Self.importToSandbox(pickedURL)
            let publication = try await ReadiumPublicationLoader.openEPUB(at: localURL)

            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: nil,
                config: .init(preferences: makePreferences())
            )
            navigator.delegate = self

            // The TOC may need to parse the nav document, hence async; if it's
            // empty, fall back to the spine so chapter jumps still work.
            let tocLinks = (try? await publication.tableOfContents().get()) ?? []

            self.navigator = navigator
            toc = tocLinks.isEmpty ? publication.readingOrder : tocLinks
            title = publication.metadata.title ?? pickedURL.deletingPathExtension().lastPathComponent
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Navigation

    func goNext() { Task { @MainActor in await navigator?.goForward() } }
    func goPrevious() { Task { @MainActor in await navigator?.goBackward() } }
    func go(to link: ReadiumShared.Link) { Task { @MainActor in await navigator?.go(to: link) } }

    // MARK: Preferences

    private func makePreferences() -> EPUBPreferences {
        EPUBPreferences(
            fontSize: fontSize,
            pageMargins: 1.4,
            scroll: scroll,
            theme: theme
        )
    }

    private func applyPreferences() {
        navigator?.submitPreferences(makePreferences())
    }

    // MARK: EPUBNavigatorDelegate

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        currentLocator = locator
    }

    // The only delegate method without a default implementation.
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        phase = .failed(error.localizedDescription)
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        chromeHidden.toggle()
    }

    // MARK: Helpers

    /// Copies the picked file into a temp folder inside the app's sandbox.
    private static func importToSandbox(_ url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ReadiumPOC", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: url, to: dest)
        return dest
    }
}

/// Thin SwiftUI host for an already-built `EPUBNavigatorViewController`.
struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let controller: EPUBNavigatorViewController

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { controller }
    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {}
}
#endif
