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
    struct WorkArt: Equatable, Sendable {
        let familyHue: Int
        let shade: Int
        let hue: Int
        let layout: Int
    }

    /// A stable hue in 0...1 derived from the title (djb2-ish hash).
    static func hue(for string: String) -> Double {
        Double(hueDegrees(for: string)) / 360
    }

    /// One deterministic art choice for every generated surface of a work. The
    /// hue family is `hue(for:)` of the primary fandom — the same function a
    /// fandom page uses for its wash. The title supplies only a ±12° shade and
    /// one of the three cover compositions.
    static func workArt(fandoms: [String], title: String) -> WorkArt {
        let fandom = fandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let familyHue = hueDegrees(for: fandom ?? title)
        let titleSeed = coverSeed(title)
        let shade = Int(titleSeed % 25) - 12
        return WorkArt(
            familyHue: familyHue,
            shade: shade,
            hue: (familyHue + shade + 360) % 360,
            layout: Int(titleSeed % 3)
        )
    }

    /// Work palettes follow the work's primary fandom so the same subject keeps
    /// the same visual identity across Home and Search. Title is only a fallback
    /// for imports and malformed blurbs that carry no fandom. The generated
    /// cover uses this as its hue family and adds the title's ±12° shade.
    static func workHue(fandoms: [String], title: String) -> Double {
        Double(workArt(fandoms: fandoms, title: title).familyHue) / 360
    }

    private static func hueDegrees(for string: String) -> Int {
        let hash = string.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return Int(hash % 360)
    }

    /// The generated-art gradient from the design export: HSL 46%/27% to
    /// hue+22° at 50%/41%, running at CSS 155°.
    static func workGradient(fandoms: [String], title: String) -> LinearGradient {
        workGradient(for: workArt(fandoms: fandoms, title: title))
    }

    static func workGradient(for art: WorkArt) -> LinearGradient {
        LinearGradient(
            colors: [
                hsl(hue: Double(art.hue), saturation: 0.46, lightness: 0.27),
                hsl(hue: Double((art.hue + 22) % 360), saturation: 0.50, lightness: 0.41)
            ],
            startPoint: UnitPoint(x: 0.2887, y: 0.0468),
            endPoint: UnitPoint(x: 0.7113, y: 0.9532)
        )
    }

    /// The component export hashes JavaScript UTF-16 code units. Matching that
    /// here keeps non-BMP titles stable between the design fixtures and Swift.
    private static func coverSeed(_ text: String) -> UInt32 {
        text.utf16.reduce(UInt32(7)) { seed, value in
            seed &* 31 &+ UInt32(value)
        }
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> Color {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let rgb: (Double, Double, Double) = switch sector {
        case 0 ..< 1: (chroma, second, 0)
        case 1 ..< 2: (second, chroma, 0)
        case 2 ..< 3: (0, chroma, second)
        case 3 ..< 4: (0, second, chroma)
        case 4 ..< 5: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        return Color(red: rgb.0 + match, green: rgb.1 + match, blue: rgb.2 + match)
    }
}

/// Common tile size for every carousel card type (Work, Reading Queue, Collection),
/// so they read as the same visual weight side by side.
enum CarouselCardMetrics {
    /// Portrait work art on a shelf. Its under-cover progress, symbols and meta
    /// bring the complete card to `height`.
    static let width: CGFloat = 120
    static let artHeight: CGFloat = width * 1.42
    static let height: CGFloat = artHeight + 55
    /// Grids are not the 120 pt shelf. Board 01 draws three columns at this
    /// floor, and each column then stretches so the row is full.
    static let gridMinimumWidth: CGFloat = 112
    /// Collections and queues remain the wider T-461 stack rather than inheriting
    /// the narrower work-cover width.
    static let stackWidth: CGFloat = 150
    static let stackHeight: CGFloat = 140
    /// Shared gaps for every compact cover grid; call sites use these, never
    /// their own numbers.
    /// 1h's cover grid, the spec's one card grid: `gap:14px 12px` — 14 between
    /// rows, 12 between columns (the same 12 the shelves put between cards).
    static let compactGridSpacing: CGFloat = 14
    static let compactGridColumnSpacing: CGFloat = 12
    /// Between collection piles, side by side (T-461): a pile fills its frame
    /// to the edge, so 12pt read as one pile running into the next.
    static let coverStackSpacing: CGFloat = 20
}

/// Scales `CarouselCardMetrics`'s fixed sqrt(2):1 tile size in proportion to the
/// user's Dynamic Type setting, preserving its aspect ratio — every compact
/// carousel card (Work, Reading Queue, Collection) embeds one of these so the
/// whole card grows together at large accessibility text sizes instead of
/// only getting taller while staying pinned at the shelf width, but never past the
/// container: at extreme accessibility sizes the proportional scale alone can
/// exceed the usable width, clipping the card's trailing edge (confirmed live
/// on iPhone 17 at accessibility-XXXL). `width`/`height` scale from the same
/// `relativeTo: .body` curve *before* clamping, then both are multiplied by
/// the identical `clampRatio` — so the sqrt(2):1 ratio holds exactly whether or
/// not the clamp is actually engaged, rather than only being preserved in the
/// unclamped case. `@ScaledMetric` only tracks environment changes when
/// declared directly on a `DynamicProperty`-conforming type — it can't be
/// shared via a static helper — so each carousel card view embeds a plain
/// `var` of this type rather than redeclaring the two `@ScaledMetric`
/// properties itself.
struct ScaledCarouselCardSize: DynamicProperty {
    @ScaledMetric(relativeTo: .body) private var scaledWidth = CarouselCardMetrics.width
    @ScaledMetric(relativeTo: .body) private var scaledHeight = CarouselCardMetrics.height
    @Environment(\.carouselCardAvailableWidth) private var availableWidth
    @Environment(\.carouselGridCardWidth) private var gridCardWidth

    init(
        width: CGFloat = CarouselCardMetrics.width,
        height: CGFloat = CarouselCardMetrics.height
    ) {
        _scaledWidth = ScaledMetric(wrappedValue: width, relativeTo: .body)
        _scaledHeight = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    /// iOS hosts measure after safe areas and gutters. macOS keeps its existing
    /// window sizing policy; no screen measurement participates in the iOS clamp.
    private var maxWidth: CGFloat {
        #if os(iOS)
        availableWidth ?? .infinity
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
        CarouselCardMetrics.clampRatio(scaledWidth: scaledWidth, availableWidth: maxWidth)
    }

    var width: CGFloat {
        if let gridCardWidth, gridCardWidth > 0 { return gridCardWidth }
        return scaledWidth * clampRatio
    }
    var height: CGFloat { scaledHeight * clampRatio }

    /// A grid computes its columns before supplying this width to its children.
    func width(in containerWidth: CGFloat?) -> CGFloat {
        scaledWidth * CarouselCardMetrics.clampRatio(
            scaledWidth: scaledWidth,
            availableWidth: containerWidth ?? .infinity
        )
    }
}

extension CarouselCardMetrics {
    static func clampRatio(scaledWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard scaledWidth > 0 else { return 1 }
        return min(1, max(0, availableWidth) / scaledWidth)
    }

    /// How many grid columns fit when none may be narrower than `minimum`.
    static func gridColumnCount(availableWidth: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        let width = max(0, availableWidth)
        let slot = max(1, minimum) + spacing
        guard width > 0 else { return 1 }
        return max(1, Int((width + spacing) / slot))
    }

    /// Column width that fills `availableWidth` across `columns`, cover aspect unchanged.
    static func gridCardWidth(availableWidth: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        let count = max(1, columns)
        let gaps = spacing * CGFloat(count - 1)
        return max(0, availableWidth - gaps) / CGFloat(count)
    }

    /// Column layout for a wrapping grid of compact cover cards (Work, Reading
    /// Queue, Collection, Account work/bookmark lists) — column count comes from
    /// the card's actual *scaled* width (see `ScaledCarouselCardSize`) via
    /// `.adaptive(minimum:)`, so it tracks every Dynamic Type step continuously
    /// instead of only collapsing at the five accessibility sizes. A fixed
    /// `count`-based grid (the previous `compactCardColumns`, removed) still let a
    /// scaled-wide card overflow its column at ordinary large text sizes — e.g.
    /// "Extra Large"/"XXL"/"XXXL" — where `isAccessibilitySize` is false but the
    /// card is already wider than half the screen; `LazyVGrid` doesn't clip an
    /// oversized child, so the two cards in a row rendered overlapping. (These
    /// cards pin their own outer width: `WorkSummaryCardSurface` renders at
    /// exactly `cardSize.width`, `HomeCards.swift`.)
    ///
    /// There is deliberately **no** `isAccessibilitySize` special case. An earlier
    /// version collapsed to one column at those sizes, inherited from the
    /// fixed-count era when a column could be narrower than the card it held. That
    /// can't happen now — every column is at least `minimum`, the card's own scaled
    /// width — so the special case only did harm: on a regular width (iPad) it
    /// forced one enormous card per row when three or four fit comfortably
    /// (owner-reported). Deriving the count purely from the scaled width gets both
    /// ends right on its own, because the width already encodes Dynamic Type: on a
    /// phone the card grows until `ScaledCarouselCardSize`'s container clamp pins it
    /// near the full width and the grid resolves to one column anyway.
    ///
    /// `tolerance` covers the opposite, sub-pixel case: on a 375pt-wide phone at
    /// the default text size two 164pt cards plus a 16pt gap need 344pt while the
    /// padded grid offers 343 — a 1pt miss that would otherwise cost a whole
    /// column and waste half the screen on the narrowest supported iPhones.
    /// Shaving it off `minimum` keeps two-up there, and the cards then overhang
    /// their column by under 1pt each, which is invisible (and is exactly what the
    /// removed fixed-2 layout already did at that width). Keep it small: it is a
    /// rounding allowance, not a lever for forcing a column that genuinely does
    /// not fit — the overlap case above is what happens when a column is forced.
    ///
    /// `maximum` is pinned to the card's own width. Without a max, `.adaptive`
    /// grows each column to soak leftover container width, so the *visual* gap
    /// between side-by-side cards becomes `spacing + leftover/N` while stacked
    /// rows stay at plain `spacing` — the cards look farther apart horizontally
    /// than vertically. Capping the column stops that absorption; any leftover
    /// width sits at the trailing edge of a leading-aligned grid instead.
    static func adaptiveCardColumns(
        minimum: CGFloat = CarouselCardMetrics.width,
        spacing: CGFloat = CarouselCardMetrics.compactGridColumnSpacing,
        tolerance: CGFloat = 2
    ) -> [GridItem] {
        let columnMin = max(1, minimum - tolerance)
        return [
            GridItem(
                .adaptive(minimum: columnMin, maximum: minimum),
                spacing: spacing
            )
        ]
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
    /// `pickedHex`: an exact "+" colour runs from itself to a darker self.
    func carouselCollectionGradient(hue: Double, pickedHex: String? = nil) -> (start: Color, end: Color) {
        if let picked = pickedHex.flatMap(Color.init(hex:)) {
            return (picked, picked.mix(with: .black, by: 0.3))
        }
        return switch self {
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
    /// `pickedHex`: an exact "+" colour, at the same wash opacity.
    func carouselQueueTint(hue: Double, pickedHex: String? = nil) -> Color {
        let (derived, opacity) = switch self {
        case .dark, .oled: (Color(hue: hue, saturation: 0.38, brightness: 0.78), 0.30)
        case .light: (Color(hue: hue, saturation: 0.42, brightness: 0.75), 0.26)
        case .sepia: (Color(hue: hue, saturation: 0.34, brightness: 0.70), 0.22)
        }
        return (pickedHex.flatMap(Color.init(hex:)) ?? derived).opacity(opacity)
    }
}
