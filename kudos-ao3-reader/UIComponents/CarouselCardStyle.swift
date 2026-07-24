import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared sizing, shadow, and theme-color tokens for Library/Home carousel cards
/// (Work, Reading Queue, Collection), so all three read as the same visual weight
/// and pull their colors from one place.

/// Shared stable hue helper for non-work decorative tiles, such as Collections and
/// Reading Queues.
enum CoverArt {
    /// A stable hue in 0...1 derived from the title (djb2-ish hash).
    static func hue(for string: String) -> Double {
        let hash = string.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return Double(hash % 360) / 360
    }
}

/// Common tile size for every carousel card type (Work, Reading Queue, Collection),
/// so they read as the same visual weight side by side.
enum CarouselCardMetrics {
    static let width: CGFloat = 164
    static let height: CGFloat = 228
    static let cornerRadius: CGFloat = CardRadius.tile
}

/// Scales `CarouselCardMetrics`'s fixed 164×228 tile size in proportion to the
/// user's Dynamic Type setting, preserving its aspect ratio — every compact
/// carousel card (Work, Reading Queue, Collection) embeds one of these so the
/// whole card grows together at large accessibility text sizes instead of
/// only getting taller while staying pinned at 164pt wide, but never past the
/// screen: at extreme accessibility sizes the proportional scale alone can
/// exceed the device width, clipping the card's trailing edge (confirmed live
/// on iPhone 17 at accessibility-XXXL). `width`/`height` scale from the same
/// `relativeTo: .body` curve *before* clamping, then both are multiplied by
/// the identical `clampRatio` — so the 164:228 ratio holds exactly whether or
/// not the clamp is actually engaged, rather than only being preserved in the
/// unclamped case. `@ScaledMetric` only tracks environment changes when
/// declared directly on a `DynamicProperty`-conforming type — it can't be
/// shared via a static helper — so each carousel card view embeds a plain
/// `var` of this type rather than redeclaring the two `@ScaledMetric`
/// properties itself.
struct ScaledCarouselCardSize: DynamicProperty {
    @ScaledMetric(relativeTo: .body) private var scaledWidth: CGFloat = CarouselCardMetrics.width
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = CarouselCardMetrics.height

    /// The widest a card may ever render: the screen/window width minus 16pt
    /// of padding on each edge (this app's established carousel/grid margin —
    /// see `WorkCarouselSection`/`LibraryEntityGridView`), so a maximally
    /// scaled card still leaves visible breathing room rather than touching
    /// or crossing the screen edge.
    private var maxWidth: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width - 32
        #elseif os(macOS)
        (NSScreen.main?.frame.width ?? 800) - 32
        #else
        800
        #endif
    }

    /// 1 when the proportionally scaled width already fits; otherwise the
    /// factor that brings it down to `maxWidth` — applied to *both*
    /// dimensions so the aspect ratio survives the clamp too.
    private var clampRatio: CGFloat {
        min(1, maxWidth / scaledWidth)
    }

    var width: CGFloat { scaledWidth * clampRatio }
    var height: CGFloat { scaledHeight * clampRatio }
}

extension CarouselCardMetrics {
    /// Column layout for a wrapping grid of compact cover cards (Work, Reading
    /// Queue, Collection) — `count` columns normally, collapsing to a single column
    /// at accessibility Dynamic Type sizes. These cards are much narrower than
    /// WorkDetail's quick-action tiles, so even two columns is already the failure
    /// mode: card text wraps character-by-character with nowhere left to grow. One
    /// column is what actually stays legible. Mirrors the same
    /// `isAccessibilitySize` pattern as `WorkDetailView.quickActionColumns`.
    static func compactCardColumns(
        for dynamicTypeSize: DynamicTypeSize,
        count: Int = 2,
        spacing: CGFloat = 16
    ) -> [GridItem] {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : count
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    /// Same collapse-to-one-column rule for an adaptive grid, whose column count
    /// otherwise comes purely from `minimum` width and never accounts for Dynamic
    /// Type — a card that fits two-up by raw pixel width can still be far too
    /// narrow for its scaled text once Dynamic Type is at an accessibility size.
    static func adaptiveCardColumns(
        for dynamicTypeSize: DynamicTypeSize,
        minimum: CGFloat = CarouselCardMetrics.width,
        spacing: CGFloat = 16
    ) -> [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: spacing)]
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: spacing)]
    }
}

struct CarouselCardShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

extension ReaderTheme {
    var carouselCardSurface: Color {
        #if os(iOS)
        appElevatedBackground ?? Color(uiColor: .secondarySystemGroupedBackground)
        #else
        appElevatedBackground ?? Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// A per-title hue wash over the elevated surface so neighbouring Work cards read
    /// as distinct works. Bright enough to give the card real color at a glance while
    /// keeping title/metadata text legible on every theme. OLED shares Dark's wash —
    /// it sits over `carouselCardSurface`, not the true-black backdrop, so the same
    /// brightness still reads clearly.
    func carouselCardTint(hue: Double) -> Color {
        switch self {
        case .dark, .oled:
            Color(hue: hue, saturation: 0.58, brightness: 0.85).opacity(0.22)
        case .light:
            Color(hue: hue, saturation: 0.62, brightness: 0.80).opacity(0.20)
        case .sepia:
            Color(hue: hue, saturation: 0.48, brightness: 0.75).opacity(0.18)
        }
    }

    func carouselCardBorder(hue: Double?) -> Color {
        if let hue {
            switch self {
            case .dark, .oled:
                return Color(hue: hue, saturation: 0.52, brightness: 0.90).opacity(0.34)
            case .light:
                return Color(hue: hue, saturation: 0.58, brightness: 0.55).opacity(0.30)
            case .sepia:
                return Color(hue: hue, saturation: 0.42, brightness: 0.55).opacity(0.28)
            }
        }
        switch self {
        case .dark, .oled:
            return Color.white.opacity(0.12)
        case .light:
            return Color.black.opacity(0.08)
        case .sepia:
            return Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.18)
        }
    }

    /// No shadow on OLED: unlike Dark's card↔backdrop pairing, OLED's backdrop is
    /// literal black, so a black shadow has nothing to darken against — the card's
    /// own tonal contrast (`carouselCardSurface` vs. the black page) already reads.
    var carouselCardShadow: CarouselCardShadow {
        switch self {
        case .dark:
            CarouselCardShadow(color: Color.black.opacity(0.34), radius: 8, y: 4)
        case .oled:
            CarouselCardShadow(color: .clear, radius: 0, y: 0)
        case .light:
            CarouselCardShadow(color: Color.black.opacity(0.13), radius: 8, y: 3)
        case .sepia:
            CarouselCardShadow(
                color: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.22),
                radius: 8,
                y: 3
            )
        }
    }

    /// Collection tile gradient: a per-name-hue two-tone wash, brighter and slightly
    /// more saturated than the Work-card tint so a shelf of works reads as its own
    /// distinct thing at a glance. Sepia stays a touch less saturated to keep the
    /// warm, paper-like palette from clashing.
    func carouselCollectionGradient(hue: Double) -> (start: Color, end: Color) {
        switch self {
        case .dark, .oled:
            (Color(hue: hue, saturation: 0.50, brightness: 0.80),
             Color(hue: hue, saturation: 0.62, brightness: 0.55))
        case .light:
            (Color(hue: hue, saturation: 0.45, brightness: 0.85),
             Color(hue: hue, saturation: 0.58, brightness: 0.62))
        case .sepia:
            (Color(hue: hue, saturation: 0.40, brightness: 0.80),
             Color(hue: hue, saturation: 0.52, brightness: 0.58))
        }
    }

    /// Reading Queue tile tint: sits over `.regularMaterial`, so it's a wash rather
    /// than a solid fill — brighter than before so the per-queue hue reads clearly
    /// through the glass instead of nearly disappearing.
    func carouselQueueTint(hue: Double) -> Color {
        switch self {
        case .dark, .oled:
            Color(hue: hue, saturation: 0.38, brightness: 0.78).opacity(0.30)
        case .light:
            Color(hue: hue, saturation: 0.42, brightness: 0.75).opacity(0.26)
        case .sepia:
            Color(hue: hue, saturation: 0.34, brightness: 0.70).opacity(0.22)
        }
    }
}
