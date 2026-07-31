import SwiftUI
#if os(iOS)
import UIKit
#endif

// Reusable wireframe skeletons for the first-load state of remote/AO3-backed content.
// Perceived-performance only: skeletons never trigger or change any AO3 request — they
// just show the shape of content that an *already in-flight* request will fill in.
// Each skeleton is hidden from VoiceOver, non-interactive, and its shimmer is disabled
// under Reduce Motion (see `skeletonShimmer()`).

// MARK: - Primitives

/// A rounded wireframe block. `width: nil` fills the available width.
struct SkeletonBlock: View {
    var height: CGFloat = 12
    var width: CGFloat?
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .frame(height: height)
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
    }
}

/// A placeholder text line — a block rounded and sized like a line of text.
struct SkeletonTextLine: View {
    var height: CGFloat = 13
    var width: CGFloat?

    var body: some View {
        SkeletonBlock(height: height, width: width, cornerRadius: height / 2.5)
    }
}

// MARK: - Shimmer (Reduce-Motion aware)

private struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.85 : (dim ? 0.5 : 0.9))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { dim = true }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

extension View {
    /// A calm, subtle pulse for skeleton placeholders. Disabled under Reduce Motion;
    /// also hides the content from VoiceOver and makes it non-interactive.
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmer())
    }
}

// MARK: - Work skeletons

/// Wireframe roughly matching `AO3WorkRow` / `WorkRow`: title, author, fandom,
/// summary lines, and a stats row.
struct AO3WorkRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonTextLine(height: 16, width: 230) // title
            SkeletonTextLine(height: 13, width: 130) // author
            SkeletonTextLine(height: 12, width: 190) // fandom
            VStack(alignment: .leading, spacing: 5) {
                SkeletonTextLine(height: 12)
                SkeletonTextLine(height: 12)
                SkeletonTextLine(height: 12, width: 210)
            }
            .padding(.top, 1)
            HStack(spacing: 16) {
                SkeletonBlock(height: 11, width: 46)
                SkeletonBlock(height: 11, width: 58)
                SkeletonBlock(height: 11, width: 40)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonShimmer()
    }
}

/// Wireframe matching the carousel cover cards (`WorkCoverCard` / `AO3WorkCoverCard`).
struct WorkCoverCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonTextLine(height: 15, width: 132) // title
            SkeletonTextLine(height: 12, width: 92) // author
            SkeletonTextLine(height: 10, width: 118) // fandom
            HStack(spacing: 8) {
                SkeletonBlock(height: 10, width: 32, cornerRadius: 4)
                SkeletonBlock(height: 10, width: 44, cornerRadius: 4)
            }
            HStack(spacing: 6) {
                SkeletonBlock(height: 18, width: 58, cornerRadius: 9)
                SkeletonBlock(height: 18, width: 62, cornerRadius: 9)
            }
            Spacer(minLength: 4)
            SkeletonTextLine(height: 10, width: 112)
            SkeletonBlock(height: 5, width: 140, cornerRadius: 3)
        }
        .padding(12)
        .frame(width: CarouselCardMetrics.width,
               height: CarouselCardMetrics.height,
               alignment: .topLeading)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius,
                                         style: .continuous))
        .skeletonShimmer()
    }
}

/// Wireframe matching the Browse category card (icon + name, stats line).
struct CategoryCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SkeletonBlock(height: 24, width: 24, cornerRadius: 6)
                SkeletonTextLine(height: 16, width: 170)
            }
            HStack(spacing: 16) {
                SkeletonBlock(height: 11, width: 90)
                SkeletonBlock(height: 11, width: 72)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonShimmer()
    }
}

/// Wireframe matching the fandom-list rows (name + work count).
struct FandomRowSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SkeletonBlock(height: 22, width: 24, cornerRadius: 6)
            SkeletonTextLine(height: 15, width: 200)
            Spacer(minLength: 24)
            HStack(spacing: 4) {
                SkeletonBlock(height: 12, width: 14, cornerRadius: 3)
                SkeletonBlock(height: 12, width: 56, cornerRadius: 4)
            }
        }
        .padding(.vertical, 8)
        .skeletonShimmer()
    }
}

// MARK: - Reader

/// A reading-page wireframe for the reader's "opening" state: a chapter heading and
/// enough paragraphs of justified-looking text lines to fill the available height,
/// so opening a work shows the shape of a full page instead of a short stub or a
/// centered spinner.
///
/// The reader host often zeroes SwiftUI safe-area regions (full-bleed page box),
/// so this skeleton pads from the **window** safe area itself — Dynamic Island /
/// status bar on top, home indicator on bottom — rather than relying on parent
/// insets that may be zero.
struct ReaderPageSkeleton: View {
    static let headingHeight: CGFloat = 22
    static let lineHeight: CGFloat = 13
    static let lineSpacing: CGFloat = 9
    static let paragraphSpacing: CGFloat = 20
    /// Extra content margin beyond the window safe area (not a substitute for it).
    private static let contentTopPad: CGFloat = 12
    private static let contentBottomPad: CGFloat = 16
    private static let shortLineEnds: [CGFloat] = [180, 120, 210, 160, 140, 200]

    var body: some View {
        GeometryReader { proxy in
            let (safeTop, safeBottom) = Self.windowVerticalSafeInsets
            let topPad = safeTop + Self.contentTopPad
            let bottomPad = safeBottom + Self.contentBottomPad
            let contentHeight = max(0, proxy.size.height - topPad - bottomPad)
            let paragraphs = Self.paragraphs(filling: contentHeight)

            VStack(alignment: .leading, spacing: Self.paragraphSpacing) {
                SkeletonTextLine(height: Self.headingHeight, width: 220)
                    .padding(.bottom, 4)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, widths in
                    VStack(alignment: .leading, spacing: Self.lineSpacing) {
                        ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                            SkeletonTextLine(height: Self.lineHeight, width: width)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .skeletonShimmer()
    }

    /// Window safe-area top/bottom. Parent readers may zero SwiftUI safe regions
    /// (peel host / full-bleed page), so GeometryReader insets alone are wrong.
    private static var windowVerticalSafeInsets: (top: CGFloat, bottom: CGFloat) {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        let insets = window?.safeAreaInsets ?? .zero
        return (insets.top, insets.bottom)
        #else
        return (0, 0)
        #endif
    }

    /// True height of a paragraph with `lineCount` lines (gaps only *between* lines).
    static func paragraphHeight(lineCount: Int) -> CGFloat {
        CGFloat(lineCount) * lineHeight + CGFloat(max(0, lineCount - 1)) * lineSpacing
    }

    /// Enough paragraph blocks to fill `height` (already exclusive of safe-area
    /// and content pads). Last line of each paragraph is short, like real prose.
    /// Internal (not `private`) so `ReaderPageSkeletonTests` can pin the fill
    /// arithmetic without a rendered view.
    static func paragraphs(filling height: CGFloat) -> [[CGFloat?]] {
        // Heading + its 4pt bottom pad + the VStack's own `paragraphSpacing` gap
        // beneath it all sit above the body paragraphs. That last term is easy to
        // miss — `spacingBefore` below is 0 for the first paragraph because the
        // heading, not a paragraph, is what precedes it — and omitting it made the
        // fill overshoot by 20pt and clip its own last line.
        var remaining = max(0, height - headingHeight - 4 - paragraphSpacing)
        var result: [[CGFloat?]] = []
        var shortIndex = 0
        while remaining >= lineHeight {
            let spacingBefore = result.isEmpty ? 0 : paragraphSpacing
            let budget = remaining - spacingBefore
            guard budget >= lineHeight else { break }

            // Largest 1…5 line count that fits under the true height formula.
            var lineCount = 1
            while lineCount < 5, paragraphHeight(lineCount: lineCount + 1) <= budget {
                lineCount += 1
            }

            var widths: [CGFloat?] = Array(repeating: nil, count: max(0, lineCount - 1))
            widths.append(shortLineEnds[shortIndex % shortLineEnds.count])
            result.append(widths)
            remaining -= spacingBefore + paragraphHeight(lineCount: lineCount)
            shortIndex += 1
            if result.count > 40 { break }
        }
        return result.isEmpty ? [[nil, nil, 160]] : result
    }
}

/// Full-screen reader open/restore/download placeholder: page skeleton on the
/// **reader** theme background (not `.systemBackground`, which flashes Light/Dark
/// OLED black under Sepia and other reader themes during the push handoff).
struct ReaderOpeningSkeleton: View {
    @Environment(ThemeManager.self) private var themeManager
    var accessibilityLabel: String = "Opening"

    private var theme: ReaderTheme { themeManager.readerTheme }

    var body: some View {
        ReaderPageSkeleton()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.backgroundColor)
            // Full-bleed on purpose. `ReaderPageSkeleton` pads from the *window*
            // safe area itself, which is right inside the reader (the peel host
            // sets `host.safeAreaRegions = []`) but would be a second inset on top
            // of this pushed screen's own — the skeleton then started ~59pt down
            // and stopped ~34pt short. Matching the reader's full-bleed page box
            // means one skeleton renders identically on both paths.
            .ignoresSafeArea()
            .preferredColorScheme(theme.colorScheme)
            #if os(iOS)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .accessibilityLabel(accessibilityLabel)
    }
}

#if os(iOS)
/// Glass bottom-card wireframe so reader chrome layout is stable while the EPUB
/// opens and before the first locator arrives (page / time / work lines).
struct ReaderPositionCardSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SkeletonTextLine(height: 15, width: 118)
                Spacer(minLength: 8)
                SkeletonTextLine(height: 12, width: 108)
            }
            SkeletonBlock(height: 5, cornerRadius: 3)
                .frame(maxWidth: .infinity)
            SkeletonTextLine(height: 12, width: 200)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .skeletonShimmer()
        .accessibilityHidden(true)
    }
}
#endif

// MARK: - Inline rows

/// A single placeholder list row (one text line) for inline loading states inside
/// Forms/Lists — account session restore, tag suggestion fetches, etc.
struct SkeletonListRow: View {
    var width: CGFloat?
    var trailingWidth: CGFloat?

    var body: some View {
        HStack(spacing: 12) {
            SkeletonTextLine(height: 14, width: width)
            if let trailingWidth {
                Spacer(minLength: 16)
                SkeletonTextLine(height: 14, width: trailingWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .skeletonShimmer()
    }
}

// MARK: - Ready-made lists (match the real card lists they replace)

/// A card list of work-row skeletons — Search, Fandom works, and Account AO3 lists.
struct AO3WorkRowSkeletonList: View {
    var count: Int = 6

    var body: some View {
        List {
            Section {
                ForEach(0 ..< count, id: \.self) { _ in AO3WorkRowSkeleton() }
                    .cardRow()
            }
        }
        .cardList()
    }
}

/// A card list of category-card skeletons — the Browse root first load.
struct CategoryCardSkeletonList: View {
    var count: Int = 8

    var body: some View {
        List {
            Section {
                ForEach(0 ..< count, id: \.self) { _ in CategoryCardSkeleton() }
                    .cardRow()
            } header: {
                Text("Browse by fandom")
            }
        }
        .cardList()
    }
}

/// A card list of fandom-row skeletons — the fandom-list first load.
struct FandomRowSkeletonList: View {
    var count: Int = 10

    var body: some View {
        List {
            ForEach(0 ..< count, id: \.self) { _ in FandomRowSkeleton() }
                .cardRow()
        }
        .cardList()
    }
}
