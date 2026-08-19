import SwiftUI

extension View {
    /// Collapses a small icon+text metadata row (e.g. `WorkStatLabel`,
    /// `CardMetaLabel`) into one VoiceOver stop instead of two — one for the
    /// decorative icon, one for the text. Ignores the row's own subview
    /// accessibility entirely (so a glyph's auto-derived SF Symbol name, e.g.
    /// "checkmark shield", never leaks into the announcement — no need to
    /// `.accessibilityHidden` the icon separately) and reports `label` instead,
    /// normally the same string already shown by the row's `Text`.
    ///
    /// Deliberately NOT a `Label` conversion: `Label`'s icon-tint renders
    /// inconsistently between `List` and plain `ScrollView` containers in this
    /// codebase — see the icon+title row comment near `AccountComponents.swift`'s
    /// `chapterSection`-style row (icon and text styled separately "rather than via
    /// a single Label, whose icon otherwise only picks up the accent tint inside a
    /// List... and falls back to .primary in Compact's plain ScrollView") — and
    /// these rows appear in both container types.
    func combinedAccessibilityRow(_ label: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// A single compact work stat: a bold glyph hugging its value, with the value
/// inheriting the surrounding font/colour. Shared across every work surface —
/// the Search/Library rows (`AO3WorkRow` / `WorkRow`) and the Home/Library
/// cover-card shelves — so metadata reads as one family (Part 4 card consistency).
struct WorkStatLabel: View {
    let text: String
    let symbol: String
    /// What VoiceOver announces instead of the bare visible `text` — a stat like
    /// "45,678" or "T" is meaningless without knowing what it's counting. Defaults
    /// to `text` for callers where the visible string is already self-describing
    /// (e.g. a full rating name, "Complete").
    var accessibilityLabel: String?
    /// Overrides the icon's usual secondary colour — rating/category chips that
    /// still need AO3's own coding pass an explicit colour. Default is secondary
    /// (not app accent): language/words/kudos etc. sit under the category row and
    /// should read as quiet metadata, not chrome.
    var iconColor: Color?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
        .combinedAccessibilityRow(accessibilityLabel ?? text)
    }
}

/// The work's last-updated date, pinned to the card's top-right corner beside
/// the expand control rather than sitting in `WorkListStatsRow` with the other
/// stats — it answers "is this still being written" at a glance, which is worth
/// the prime corner. Shared by `WorkRow` and `AO3WorkRow` so the two agree.
///
/// Shows only when it differs from the published date, which stays in the stats
/// row: a never-updated oneshot has nothing new to say twice. `AO3WorkSummary`
/// carries no published date at all, so a search result always shows this.
struct WorkUpdatedDateBadge: View {
    let dateUpdated: String
    var datePublished: String?

    var body: some View {
        if !dateUpdated.isEmpty, dateUpdated != datePublished {
            let display = WorkStat.displayDate(dateUpdated)
            WorkStatLabel(
                text: display,
                symbol: "calendar.badge.clock",
                accessibilityLabel: "Updated \(display)"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// Rating, category, warnings, and completion status as color-coded capsule
/// chips — the four fields AO3 itself always surfaces up front on a work.
/// Every badge always shows something, even "Uncategorized"/"No Warnings" —
/// a blank slot reads as a layout gap rather than a real state on device.
///
/// Shared by `WorkListStatsRow` (search/library list rows, paired with its
/// own longer secondary-facts row below) and the resume hero cards
/// (`HomeResumeHero`/`WorkDetailHeroCard`, paired with a shorter
/// Language/Words/Chapters row instead) — both need this exact same row of
/// chips, just different company underneath.
struct WorkTopStatsRow: View {
    var rating: String?
    var categories: [String] = []
    var warnings: [String] = []
    var completion: WorkCompletionStatus = .unknown
    /// The host card is showing its full detail. Only the category chip changes:
    /// collapsed it folds several categories into "Multi" the way AO3's own blurb
    /// does, expanded it names each one. Defaults to compact, which is what every
    /// list wants.
    var isExpanded: Bool = false
    /// True gives each chip its own row instead of wrapping several onto one
    /// line — the compact cover cards, narrow enough that a wrapping row
    /// often only fit one or two chips per line anyway. Search/library rows
    /// and the hero cards have the width for several per line, so they keep
    /// the default wrapping `FlowLayout`.
    var stacked: Bool = false

    struct Item {
        let text: String
        let symbol: String
        let accessibilityLabel: String
        var iconColor: Color?
    }

    /// Checking `categories` for emptiness isn't enough: an unrecognized
    /// category string would pass `!isEmpty` but still render nothing, leaving
    /// the slot silently blank. Filter to recognized values first.
    ///
    /// AO3's own legend never lists the specific warnings in its badge either —
    /// just how many apply — so the visible warning text stays short; the full
    /// list still reaches VoiceOver through the accessibility label.
    /// The category chips only, for tests: the collapse rule is the thing worth
    /// pinning and `topItems` mixes in three other facets.
    var categoryChipTexts: [String] {
        topItems.filter { $0.symbol == "person.2.fill" }.map(\.text)
    }

    /// The warning chips only — same reason as `categoryChipTexts`. All three
    /// warning states share one symbol (colour carries the distinction), and no
    /// other facet uses it, so it identifies the group.
    var warningChipTexts: [String] {
        topItems.filter { $0.symbol == "exclamationmark.circle.fill" }.map(\.text)
    }

    var topItems: [Item] {
        var result: [Item] = []
        if let rating {
            result.append(Item(
                text: WorkStat.ratingLetter(rating) ?? rating,
                symbol: "checkmark.shield",
                accessibilityLabel: rating,
                iconColor: WorkStat.ratingColor(rating)
            ))
        }
        let recognized = categories.filter { WorkStat.categoryColor($0) != nil }
        if recognized.count > 1, !isExpanded {
            // AO3's own rule, verified live on 2026-08-07: its blurb draws
            // `category-multi` for *any* work with more than one category, whether
            // or not the literal "Multi" tag is among them — `F/F, M/M` and
            // `Gen, M/M` both get it, with the real list only in the title
            // attribute. One chip keeps a collapsed card glanceable; expanding
            // spells them out, which is what AO3's own work page does too.
            result.append(Item(
                text: "Multi",
                symbol: "person.2.fill",
                accessibilityLabel: "Categories: \(recognized.joined(separator: ", "))",
                iconColor: WorkStat.categoryColor("Multi")
            ))
        } else if recognized.isEmpty {
            result.append(Item(
                text: "N/A",
                symbol: "person.2.fill",
                accessibilityLabel: "Category: not categorized",
                iconColor: .gray
            ))
        } else {
            for category in recognized {
                result.append(Item(
                    text: category,
                    symbol: "person.2.fill",
                    accessibilityLabel: WorkStat.categoryAccessibilityLabel(category),
                    iconColor: WorkStat.categoryColor(category)
                ))
            }
        }
        let status = WorkWarningStatus(rawWarnings: warnings)
        let realWarnings = WorkStat.realWarnings(warnings)
        if isExpanded, case .present = status {
            // Expanded, the count becomes the warnings themselves — the same
            // collapsed/expanded split the categories take. Only `.present` has
            // anything to expand: "No Warnings" and "Not Disclosed" are single
            // states, not folded lists, and would say the same thing either way.
            for warning in realWarnings {
                result.append(Item(
                    text: warning,
                    symbol: status.symbol,
                    accessibilityLabel: "Warning: \(warning)",
                    iconColor: status.color
                ))
            }
        } else {
            result.append(Item(
                text: status.text,
                symbol: status.symbol,
                accessibilityLabel: status.accessibilityLabel(rawWarnings: warnings),
                iconColor: status.color
            ))
        }
        result.append(Item(
            text: completion.shortText,
            symbol: completion.symbol,
            accessibilityLabel: "Status: \(completion.text)",
            iconColor: completion.color
        ))
        return result
    }

    /// One AO3 status as a capsule. The *capsule* carries AO3's rating/category
    /// colour coding now, not the glyph — a chip is a block of colour, so painting
    /// it is what the colour coding is for. The glyph and text stay on the row's
    /// inherited `.secondary`, which is legible on every tint and in every theme;
    /// a saturated glyph on a tinted capsule of the same hue just goes muddy.
    ///
    /// Tinted, not filled: `.explicit` is red and `.mature` orange, and four
    /// solid blocks of those beside the cover art would read as an error state.
    /// The alpha is low enough that secondary text keeps its contrast in both
    /// appearances, and an uncoloured item (nothing AO3 colour-codes) falls back
    /// to the neutral `.quaternary` the whole row used to use.
    private func statusChip(_ item: Item) -> some View {
        HStack(spacing: 3) {
            Image(systemName: item.symbol)
                .font(.caption2.weight(.bold))
            Text(item.text)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(chipFill(item), in: Capsule())
        .combinedAccessibilityRow(item.accessibilityLabel)
    }

    private func chipFill(_ item: Item) -> AnyShapeStyle {
        guard let color = item.iconColor else { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(color.opacity(0.22))
    }

    /// Centred. Justification stretched the gaps to square the row's edges
    /// with the counts underneath, which only works while both rows are
    /// full — a two-chip work got two capsules pinned to opposite edges of
    /// the card with a canyon between them. Centring keeps the natural gaps
    /// at any chip count and still reads as a deliberate row. No bullet
    /// separators between chips — each capsule already has its own colored
    /// background, so a bullet was redundant separation, and dropping it
    /// lets more chips fit on one row before wrapping.
    ///
    /// `FlowLayout` rather than an `HStack` inside a `ViewThatFits`: that sizes its
    /// chosen candidate to the candidate's *ideal* width, never the width on offer,
    /// so there was nothing to centre within. FlowLayout also still wraps when the
    /// chips genuinely don't fit — they are all `fixedSize`, so a too-long single
    /// row would otherwise stretch the card past its own padding.
    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 5) {
                // Rating and category share a row — both are short tags
                // ("T", "M/M") that comfortably fit side by side, unlike
                // Warnings/Completion, which run longer ("Not Disclosed",
                // "In Progress"). A FlowLayout, not an HStack, only so a rare
                // expanded/long combination still wraps instead of
                // overflowing the card.
                let ratingAndCategory = topItems.filter {
                    $0.symbol == "checkmark.shield" || $0.symbol == "person.2.fill"
                }
                let rest = topItems.filter {
                    $0.symbol != "checkmark.shield" && $0.symbol != "person.2.fill"
                }
                if !ratingAndCategory.isEmpty {
                    FlowLayout(spacing: 6, rowSpacing: 5) {
                        ForEach(Array(ratingAndCategory.enumerated()), id: \.offset) { _, item in
                            statusChip(item)
                        }
                    }
                }
                ForEach(Array(rest.enumerated()), id: \.offset) { _, item in
                    statusChip(item)
                }
            }
        } else {
            FlowLayout(spacing: 6, rowSpacing: 5, rowAlignment: .center) {
                ForEach(Array(topItems.enumerated()), id: \.offset) { _, item in
                    statusChip(item)
                }
            }
        }
    }
}

/// Rating/category/warnings/completion as a compact icon-only 2×2 grid — AO3's
/// own quadrant "tag grid" idea (Symbols Key: rating upper-left, category
/// upper-right, warnings lower-right, completion lower-left — this follows the
/// same reading order), reimagined in this app's own chip colors and symbols
/// rather than AO3's flat colored-square-with-white-glyph badges.
///
/// Purely decorative — `topItems`' `WorkTopStatsRow.Item.accessibilityLabel`
/// never reaches VoiceOver here (`.accessibilityHidden`), so callers must keep
/// a real accessible summary of the same facts elsewhere (`WorkTopStatsRow`'s
/// own text chips, or the card's title/stats row).
struct WorkStatusIconGrid: View {
    var rating: String?
    var categories: [String] = []
    var warnings: [String] = []
    var completion: WorkCompletionStatus = .unknown
    var isExpanded: Bool = false
    /// Each tile's edge length; gap/corner-radius/glyph sizes all scale with it
    /// so the grid stays proportional at any size a caller asks for.
    var tileSize: CGFloat = 18
    /// True when this grid is a card's *only* summary of rating/category/
    /// warnings/completion, with no separate always-visible text row to
    /// carry the accessible version — announces the same facts as one
    /// VoiceOver stop instead of staying fully hidden. Default false matches
    /// every existing caller, which keeps its own accessible text elsewhere.
    var announcesToVoiceOver: Bool = false

    private var items: [WorkTopStatsRow.Item] {
        WorkTopStatsRow(
            rating: rating, categories: categories, warnings: warnings,
            completion: completion, isExpanded: isExpanded
        ).topItems
    }

    private var gap: CGFloat { tileSize * 3 / 18 }
    private var cornerRadius: CGFloat { tileSize * 4 / 18 }
    private var iconSize: CGFloat { tileSize * 10 / 18 }
    private var shieldSize: CGFloat { tileSize * 12 / 18 }
    private var letterSize: CGFloat { tileSize * 6 / 18 }
    /// The Unicode pairing glyphs (⚢/⚣/⚤/♅) read smaller than the SF Symbol
    /// icons around them at the same point size — Apple Symbols draws them
    /// with more internal padding than SF Symbols' own icon metrics.
    private var pairingSymbolSize: CGFloat { tileSize * 12 / 18 }
    /// Gen's sun glyph (☉) specifically reads much smaller than the other
    /// icons at `pairingSymbolSize` — Apple Symbols draws it with far more
    /// internal padding than the doubled-gender glyphs get. Measured its
    /// rendered ink against the warning tile's own exclamationmark-circle
    /// ink at both tile sizes: a font size equal to `tileSize` itself (not
    /// `pairingSymbolSize`) lands within a couple percent of matching it.
    private var genSymbolSize: CGFloat { tileSize }
    /// Multi tile geometry — a vector ring+stem motif, not a font glyph, so
    /// these are plain design ratios rather than anything measured. Two
    /// quadrants across exactly fill the tile.
    private var multiQuadrantSize: CGFloat { tileSize / 2 }
    private var multiRingDiameter: CGFloat { tileSize / 3 }
    /// Matched to the rating shield's own outline thickness — measured by
    /// rendering `Image(systemName: "shield")` at `shieldSize` and finding
    /// the ink width of its side stroke: ~5.1-5.2% of tileSize at both 18pt
    /// and 27pt tiles, i.e. close to tileSize/19. The previous tileSize/14
    /// read noticeably heavier than every SF Symbol icon around it.
    private var multiLineWidth: CGFloat { max(tileSize / 19, 0.75) }

    var body: some View {
        let items = items
        let grid = VStack(spacing: gap) {
            HStack(spacing: gap) {
                tile(!items.isEmpty ? items[0] : nil)
                tile(items.count > 1 ? items[1] : nil)
            }
            HStack(spacing: gap) {
                tile(items.count > 2 ? items[2] : nil)
                tile(items.count > 3 ? items[3] : nil)
            }
        }
        if announcesToVoiceOver {
            grid.combinedAccessibilityRow(items.map(\.accessibilityLabel).joined(separator: ", "))
        } else {
            grid.accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func tile(_ item: WorkTopStatsRow.Item?) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let item {
            shape
                // Multi's own icon IS a full multicolor quadrant — a tint
                // behind it would just be a fifth, redundant color peeking
                // around its edges.
                .fill(
                    item.text == "Multi" ? AnyShapeStyle(.clear) : AnyShapeStyle((item.iconColor ?? .gray).opacity(0.3))
                )
                .overlay {
                    // Rating (AO3's own quadrant reads a letter, not a checkmark):
                    // no `{letter}.shield` SF Symbol exists — confirmed against
                    // the live catalog, unlike `{letter}.circle`/`.square`, which
                    // do — so the letter is composited by hand over a filled
                    // shield instead of a single systemName.
                    if item.symbol == "checkmark.shield" {
                        ratingShield(item)
                    } else if item.symbol == "person.2.fill" {
                        categoryGlyph(item)
                    } else {
                        Image(systemName: item.symbol)
                            .font(.system(size: iconSize, weight: .bold))
                            .foregroundStyle(item.iconColor ?? .gray)
                    }
                }
                .frame(width: tileSize, height: tileSize)
        } else {
            Color.clear.frame(width: tileSize, height: tileSize)
        }
    }

    private func ratingShield(_ item: WorkTopStatsRow.Item) -> some View {
        // "NR" (WorkStat.ratingLetter's own text for Not Rated) is two
        // characters — cramped at this size, and "?" already reads as
        // "unrated/unknown" without needing to fit two glyphs.
        let letter = item.text == "NR" ? "?" : item.text
        return ZStack {
            // Unfilled outline, not `.shield.fill` — a solid block was the odd
            // one out next to the other 3 tiles' own colored-line-on-tinted-
            // background treatment. The letter now sits on that same tint
            // rather than a solid fill, so it's colored to match instead of
            // needing white for contrast.
            Image(systemName: "shield")
                .font(.system(size: shieldSize))
                .foregroundStyle(item.iconColor ?? .gray)
            // No vertical offset: an earlier version pushed this up by
            // -tileSize/36 on the theory that the shield's taper shifts its
            // visual centroid above geometric center, but rasterizing both
            // layers with ImageRenderer and measuring their actual ink
            // bounding boxes (at 8x supersampling, two tile sizes) found the
            // opposite — the unfilled shield's ink is already dead-centered
            // in its layout frame (SF Symbols bake balanced bounding-box
            // padding into asymmetric shapes like this one), and so is every
            // rating letter (G/T/M/E/?) vertically, to within a quarter point
            // of sub-pixel rendering noise that changes sign between sizes
            // rather than tracking the taper.
            //
            // The same measurement did find a real *horizontal* bias, though:
            // every letter's ink sits left of the shield's (dead-centered)
            // ink by ~0.3pt, consistently in the same direction at both
            // 18pt and 27pt tiles — small enough to read as noise on its
            // own, but visible once the eye has the shield's edges as a
            // reference (reported: "more space to the right than the
            // left"). Unlike the vertical bias this one didn't scale with
            // tileSize between the two sizes tested, so it's a small fixed
            // point offset rather than a proportional one.
            Text(letter)
                .font(.system(size: letterSize, weight: .bold, design: .rounded))
                .foregroundStyle(item.iconColor ?? .gray)
                .offset(x: 0.3)
        }
    }

    /// Category (AO3's own quadrant pairs a gender symbol per orientation, not
    /// one generic icon for all of them): no SF Symbol ships literal gender
    /// glyphs — Apple dropped them from the catalog — and the raw ♀/♂
    /// characters aren't in SF Pro either (confirmed: they resolve to
    /// `CJKSymbolsFallbackSC`, not SF, regardless of what font is requested —
    /// fallback happens per-glyph for characters the requested font doesn't
    /// contain). Unicode's Miscellaneous Symbols block already has real,
    /// single, purpose-drawn glyphs for the *combined* signs though — used
    /// here instead of manually overlapping two separate characters. Same
    /// fallback situation (`AppleSymbols`, not SF — accepted as-is: a clean,
    /// purpose-built system font, not a mismatched decorative one), but a
    /// properly kerned glyph instead of a hand-offset approximation of one.
    /// `item.text` is AO3's own raw category string ("F/F"/"M/M"/"F/M"/"Gen"/
    /// "Multi"/"Other"/"N/A"), already resolved by `WorkTopStatsRow.topItems`
    /// — reused here rather than re-deriving the category from anywhere else.
    @ViewBuilder
    private func categoryGlyph(_ item: WorkTopStatsRow.Item) -> some View {
        switch item.text {
        case "F/F":
            categoryText("⚢", size: pairingSymbolSize, verticalOffset: 0.193, item) // U+26A2 DOUBLED FEMALE SIGN
        case "M/M":
            categoryText("⚣", size: pairingSymbolSize, verticalOffset: 0.249, item) // U+26A3 DOUBLED MALE SIGN
        case "F/M":
            categoryText("⚤", size: pairingSymbolSize, verticalOffset: 0.102, item) // U+26A4 INTERLOCKED F+M SIGN
        case "Gen":
            // AO3's own icon here is the Sun astronomical symbol on a green
            // background — no pairing to symbolize since Gen means no
            // romantic/sexual focus. See archiveofourown.org/help/symbols_key.
            // Sized to genSymbolSize, not pairingSymbolSize: measured against
            // the warning tile's own ink, this glyph reads much smaller than
            // the other pairing glyphs at the same font size.
            categoryText("☉", size: genSymbolSize, verticalOffset: 0.120, item) // U+2609 SUN
        case "Multi":
            multiIcon
        case "Other":
            // AO3's own icon here is the Uranus astrological symbol on a black
            // background — the design team's pick for relationships that don't
            // fit the other categories. See archiveofourown.org/help/symbols_key.
            categoryText("♅", size: pairingSymbolSize, verticalOffset: 0.129, item) // U+2645 URANUS
        default:
            // "N/A" — nothing to symbolize.
            Image(systemName: item.symbol)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(item.iconColor ?? .gray)
        }
    }

    /// - Parameter size: font size to render `symbol` at — `pairingSymbolSize`
    ///   for every glyph except Gen's sun, which needs its own larger size.
    /// - Parameter verticalOffset: fraction of `size` to shift down by. Apple
    ///   Symbols' line-box metrics (ascent/descent) don't match these
    ///   glyphs' own ink bounds — every one of them sits above the center of
    ///   the box `Text` centers by default, so an un-offset glyph reads
    ///   high, and by an amount that varies per glyph (measured via
    ///   CTFontGetBoundingRectsForGlyphs against CTFontGetAscent/GetDescent:
    ///   ⚢ 19.3%, ⚣ 24.9%, ⚤ 10.2%, ☉ 12.0%, ♅ 12.9% of point size) rather
    ///   than one constant that would only look right for one of them.
    private func categoryText(_ symbol: String, size: CGFloat, verticalOffset: CGFloat, _ item: WorkTopStatsRow.Item)
        -> some View {
        // `.system` hands these glyphs to the font-fallback cascade, which
        // doesn't always land on Apple Symbols even when it has the glyph —
        // confirmed via CoreText that ♅ resolves to Menlo instead, despite
        // Apple Symbols containing it. Naming the font directly skips the
        // cascade and guarantees the glyph AO3's own icon set intends.
        Text(symbol)
            .font(.custom("AppleSymbols", size: size))
            .foregroundStyle(item.iconColor ?? .gray)
            .offset(y: size * verticalOffset)
    }

    /// Multi has no single relationship to symbolize — AO3's own icon here is
    /// a small multi-color grid. This builds an equivalent from four
    /// `RingMotif`/`StemMotif` ring+stem pairs (a vector stand-in for
    /// NEUTER, U+26B2 — no font involved), each rotated 90° further than the
    /// last and positioned so its stem tip touches the next glyph's ring
    /// edge, forming a closed loop. Each quadrant is tinted per relationship
    /// type rather than one shared color: General (green, matching
    /// `categoryColor("Gen")`), F/M (purple), F/F (red), M/M (blue) — each
    /// square tinted at the same `.opacity(0.3)` every other tile's
    /// background uses, with its motif in the same color at full strength on
    /// top, matching the colored-line-on-tinted-background look the other
    /// three category tiles already use.
    ///
    /// Quadrant centers sit at (±quadrantSize/2, ±quadrantSize/2), and since
    /// quadrantSize is exactly tileSize/2, two quadrants across always fill
    /// the tile exactly — no per-size measurement or post-hoc scaling needed
    /// the way the font-glyph version this replaced required.
    private var multiIcon: some View {
        let half = multiQuadrantSize / 2
        // The ring's own center, in its unrotated local frame (a
        // multiRingDiameter × multiQuadrantSize box with the ring at the top
        // and the stem running down to the bottom edge), relative to that
        // frame's center.
        let localRingOffset = CGPoint(x: 0, y: multiRingDiameter / 2 - half)
        let quadrants: [MultiQuadrant] = [
            MultiQuadrant(rotation: -90, squareCenter: CGPoint(x: -half, y: -half), color: .green), // top-left — Gen
            MultiQuadrant(rotation: 0, squareCenter: CGPoint(x: half, y: -half), color: .purple), // top-right — F/M
            MultiQuadrant(rotation: 180, squareCenter: CGPoint(x: -half, y: half), color: .red), // bottom-left — F/F
            MultiQuadrant(rotation: 90, squareCenter: CGPoint(x: half, y: half), color: .blue), // bottom-right — M/M
        ]
        return ZStack {
            ForEach(quadrants.indices, id: \.self) { i in
                let quadrant = quadrants[i]
                // Only the corner facing away from the tile's center is
                // rounded — the other three meet a neighbor or the shared
                // center point and stay sharp, so the four quadrants read as
                // one shape from outside.
                let center = quadrant.squareCenter
                UnevenRoundedRectangle(
                    topLeadingRadius: center.x < 0 && center.y < 0 ? cornerRadius : 0,
                    bottomLeadingRadius: center.x < 0 && center.y > 0 ? cornerRadius : 0,
                    bottomTrailingRadius: center.x > 0 && center.y > 0 ? cornerRadius : 0,
                    topTrailingRadius: center.x > 0 && center.y < 0 ? cornerRadius : 0,
                    style: .continuous
                )
                .fill(quadrant.color.opacity(0.3))
                .frame(width: multiQuadrantSize, height: multiQuadrantSize)
                .offset(x: center.x, y: center.y)
            }
            // Every stem is drawn before every ring — not per-quadrant, all
            // 4 stems then all 4 rings — so every ring sits on top of any
            // stem it touches, regardless of which quadrant pair that is.
            // The loop's own direction means quadrant N's stem always
            // touches quadrant N+1's ring, so no single per-quadrant z-order
            // could satisfy all 4 junctions at once (it's circular: TL's
            // ring must be both above BL's stem and below its own stem's
            // target) — splitting ring and stem into their own passes
            // sidesteps that instead of solving it.
            ForEach(quadrants.indices, id: \.self) { i in
                let quadrant = quadrants[i]
                motifShape(quadrant, localRingOffset: localRingOffset) {
                    // Butt cap, not round: a round cap extends the stem's
                    // stroke past its own start point by half the line
                    // width, bulging it into the ring it's meant to just
                    // touch (reported: "the stems overlap the circles").
                    StemMotif().stroke(quadrant.color, style: StrokeStyle(lineWidth: multiLineWidth, lineCap: .butt))
                }
            }
            ForEach(quadrants.indices, id: \.self) { i in
                let quadrant = quadrants[i]
                motifShape(quadrant, localRingOffset: localRingOffset) {
                    RingMotif().stroke(quadrant.color, lineWidth: multiLineWidth)
                }
            }
        }
        .frame(width: tileSize, height: tileSize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Positions one quadrant's ring or stem piece identically — same frame,
    /// rotation, and offset a combined ring+stem motif would use — so the
    /// two independently-z-ordered passes above land exactly where a single
    /// motif would have.
    @ViewBuilder
    private func motifShape(
        _ quadrant: MultiQuadrant, localRingOffset: CGPoint, @ViewBuilder content: () -> some View
    ) -> some View {
        let rotatedRing = rotate(localRingOffset, degrees: quadrant.rotation)
        let motifOffset = CGSize(
            width: quadrant.squareCenter.x - rotatedRing.x,
            height: quadrant.squareCenter.y - rotatedRing.y
        )
        content()
            .frame(width: multiRingDiameter, height: multiQuadrantSize)
            .rotationEffect(.degrees(quadrant.rotation))
            .offset(motifOffset)
    }

    private func rotate(_ point: CGPoint, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: point.x * cos(radians) - point.y * sin(radians),
            y: point.x * sin(radians) + point.y * cos(radians)
        )
    }
}

private struct MultiQuadrant {
    let rotation: Double
    let squareCenter: CGPoint
    let color: Color
}

/// A relationship-category ring+stem motif, drawn as plain vector geometry
/// (no font involved) so it scales losslessly at any tile size — split into
/// two shapes (rather than one combined path) so `multiIcon` can draw every
/// quadrant's stem before every quadrant's ring, keeping each ring on top of
/// any stem it touches. Both fill whatever rect they're given, sized and
/// positioned as one unit: a ring whose diameter equals the rect's width,
/// sitting at the top, and a stem running from the ring's bottom edge to the
/// rect's bottom edge. `WorkStatusIconGrid.multiIcon` rotates and positions
/// four of these pairs (one per relationship-category color) so each one's
/// stem tip touches the next one's ring, forming a closed loop.
private struct RingMotif: Shape {
    func path(in rect: CGRect) -> Path {
        let diameter = rect.width
        let radius = diameter / 2
        let ringCenter = CGPoint(x: rect.midX, y: rect.minY + radius)
        return Path(ellipseIn: CGRect(
            x: ringCenter.x - radius, y: ringCenter.y - radius, width: diameter, height: diameter
        ))
    }
}

private struct StemMotif: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let ringBottom = rect.minY + rect.width
        path.move(to: CGPoint(x: rect.midX, y: ringBottom))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// The rating/word-count/chapters/kudos stat row on a detailed list row. Shared
/// by `WorkRow` (local `SavedWork`) and `AO3WorkRow` (remote `AO3WorkSummary`)
/// — each derives these already-formatted, already-nil-checked values from its
/// own model shape and hands them here, so the two never drift out of layout
/// sync with each other.
struct WorkListStatsRow: View {
    var rating: String?
    var categories: [String] = []
    var warnings: [String] = []
    var completion: WorkCompletionStatus = .unknown
    var language: String?
    var wordCount: Int?
    var chapters: String?
    var comments: Int?
    var kudos: Int?
    /// The work's AO3 bookmark count — not the in-book bookmarks/highlights
    /// that `KudosBackupBookmark` and the reader mean by the same word.
    var bookmarks: Int?
    var hits: Int?
    /// Published only — the updated date lives in the card's top-right corner
    /// (`WorkUpdatedDateBadge`), not down here with the rest of the stats.
    var datePublished: String?
    var isExpanded: Bool = false

    /// Settings → Library → "Show zero counts". On (the default) every stat
    /// keeps its place even at zero, so a card's stat row has the same shape
    /// whatever the work; off drops the empty ones for a terser row.
    @AppStorage("showsZeroStats") private var showsZeroStats = true

    private var showsPublished: Bool {
        guard let datePublished else { return false }
        return !datePublished.isEmpty
    }

    private typealias Item = WorkTopStatsRow.Item

    /// A count stat, treating "AO3 didn't print it" as the zero it means.
    /// Returns nil — dropping the badge — only when the count is zero and the
    /// user has turned "Show zero counts" off.
    private func count(_ value: Int?, symbol: String, noun: String) -> Item? {
        let count = value ?? 0
        guard count > 0 || showsZeroStats else { return nil }
        let formatted = count.formatted()
        return Item(text: formatted, symbol: symbol, accessibilityLabel: "\(formatted) \(noun)")
    }

    /// Language / words / chapters / engagement counts / published date, below
    /// the justified row.
    ///
    /// With "Show zero counts" on (the default) every stat holds its place,
    /// zeros included: AO3 omits a `dd` entirely when its count is zero, so a
    /// nil here means "AO3 said nothing", which for a count means zero — and
    /// dropping those badges made a card's stat row change shape for no reason
    /// a reader could see. The two text stats (language, chapters) can be
    /// genuinely absent rather than zero, so they fall back to an em dash.
    private var secondaryItems: [Item] {
        let unknownText = "—"
        let language = language.flatMap { $0.isEmpty ? nil : $0 }
        let chapters = chapters.flatMap { $0.isEmpty ? nil : $0 }
        var result: [Item] = []
        if language != nil || showsZeroStats {
            // AO3 scrapes `dd.language` as a display name already ("English",
            // "Español"), so there is no code to map here.
            result.append(Item(
                text: language ?? unknownText,
                symbol: "globe",
                accessibilityLabel: language.map { "Language: \($0)" } ?? "Language unknown"
            ))
        }
        result.append(contentsOf: [
            count(wordCount, symbol: "textformat.size", noun: "words")
        ].compactMap(\.self))
        if chapters != nil || showsZeroStats {
            result.append(Item(
                text: chapters ?? unknownText,
                symbol: "book",
                accessibilityLabel: chapters.map { "Chapters \($0)" } ?? "Chapter count unknown"
            ))
        }
        result.append(contentsOf: [
            count(comments, symbol: "bubble.left", noun: "comments"),
            count(kudos, symbol: "heart", noun: "kudos"),
            count(bookmarks, symbol: "bookmark", noun: "bookmarks"),
            count(hits, symbol: "eye", noun: "hits")
        ].compactMap(\.self))
        if showsPublished, let datePublished {
            let display = WorkStat.displayDate(datePublished)
            result.append(Item(text: display, symbol: "calendar", accessibilityLabel: "Published \(display)"))
        }
        return result
    }

    private var topStatsRow: WorkTopStatsRow {
        WorkTopStatsRow(rating: rating, categories: categories, warnings: warnings,
                         completion: completion, isExpanded: isExpanded)
    }

    /// For tests: the collapse rule is the thing worth pinning. See
    /// `WorkTopStatsRow.categoryChipTexts`/`.warningChipTexts`.
    var categoryChipTexts: [String] { topStatsRow.categoryChipTexts }
    var warningChipTexts: [String] { topStatsRow.warningChipTexts }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topStatsRow
            if !secondaryItems.isEmpty {
                FlowLayout(spacing: 8, rowSpacing: 5) {
                    ForEach(Array(secondaryItems.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Text("•")
                                .accessibilityHidden(true)
                        }
                        WorkStatLabel(
                            text: item.text,
                            symbol: item.symbol,
                            accessibilityLabel: item.accessibilityLabel,
                            iconColor: item.iconColor
                        )
                    }
                }
            }
        }
        .font(.caption2)
        // Matches the summary text above the divider (.secondary) — .tertiary
        // read as too faint next to it.
        .foregroundStyle(.secondary)
        .padding(.top, 1)
    }
}

/// Complete / In Progress / Unknown — shared by the compact cover cards and the
/// detail/search stats row so both read the same tri-state the same way.
enum WorkCompletionStatus: Equatable {
    case complete
    case inProgress
    case unknown

    /// `isComplete` is `nil` only when the status is genuinely not known (an
    /// import whose source never stated it) — not simply "not yet checked".
    init(isComplete: Bool?) {
        switch isComplete {
        case true: self = .complete
        case false: self = .inProgress
        case nil: self = .unknown
        }
    }

    var text: String {
        switch self {
        case .complete: "Complete"
        case .inProgress: "In Progress"
        case .unknown: "Unknown"
        }
    }

    /// For the dense four-badge top row, where "In Progress" is the one label
    /// long enough to push the row past a single line. The compact cover cards
    /// keep `text` — they deliberately spell their stats out (see
    /// `CoverCardStatsRow`) and have the width for it.
    var shortText: String {
        switch self {
        case .complete: "Complete"
        case .inProgress: "WIP"
        case .unknown: "Unknown"
        }
    }

    /// The compact cover cards already shipped checkmark.seal/circle.dashed for
    /// the two known states — kept as-is; questionmark.circle.fill fills the
    /// one gap (unknown status previously showed no badge at all).
    var symbol: String {
        switch self {
        case .complete: "checkmark.seal"
        case .inProgress: "circle.dashed"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .complete: .green
        case .inProgress: .orange
        case .unknown: .gray
        }
    }
}

/// AO3's Archive Warnings field is one of three mutually-exclusive states, not
/// a plain present/absent flag — its own legend colors each differently:
/// specific warnings listed (red), "No Archive Warnings Apply" (gray/none),
/// or "Creator Chose Not To Use Archive Warnings" (amber — the content
/// *could* include any of the standard warnings, the creator just didn't say).
/// Collapsing the latter two together would misrepresent an undisclosed work
/// as a confirmed-clean one.
enum WorkWarningStatus: Equatable {
    case none
    case undisclosed
    case present(count: Int)

    init(rawWarnings: [String]) {
        if rawWarnings.contains(where: { $0.localizedCaseInsensitiveContains("Chose Not To Use") }) {
            self = .undisclosed
            return
        }
        let real = WorkStat.realWarnings(rawWarnings)
        self = real.isEmpty ? .none : .present(count: real.count)
    }

    var text: String {
        switch self {
        case .none: "No Warnings"
        case .undisclosed: "Not Disclosed"
        case .present(let count): count == 1 ? "1 Warning" : "\(count) Warnings"
        }
    }

    /// One icon for all three states — like the rating shield and category
    /// glyph, color alone carries the distinction.
    var symbol: String { "exclamationmark.circle.fill" }

    var color: Color {
        switch self {
        case .none: .gray
        case .undisclosed: .orange
        case .present: .red
        }
    }

    func accessibilityLabel(rawWarnings: [String]) -> String {
        switch self {
        case .none: "No archive warnings"
        case .undisclosed: "Archive warnings: creator chose not to disclose — content could include any of the standard warnings"
        case .present: "Warnings: \(WorkStat.realWarnings(rawWarnings).joined(separator: ", "))"
        }
    }
}

extension SavedWork {
    /// An AO3 work always has a known status. A converted import only has one
    /// when its source stated it, which the metadata page now carries through —
    /// so "Complete"/"In Progress" show when actually known, "Unknown" otherwise,
    /// rather than defaulting a non-AO3 work to "In Progress" and being wrong.
    var completionStatus: WorkCompletionStatus {
        let hasKnownStatus = ao3WorkID != nil || WorkTags.ao3WorkID(from: sourceURL) != nil
        if hasKnownStatus { return isComplete ? .complete : .inProgress }
        return isComplete ? .complete : .unknown
    }
}

enum WorkStat {
    /// AO3's "No Archive Warnings Apply" / "Creator Chose Not To Use Archive
    /// Warnings" are sentinel non-warnings, not warnings worth flagging red.
    static func realWarnings(_ warnings: [String]) -> [String] {
        warnings.filter {
            !$0.localizedCaseInsensitiveContains("No Archive Warnings")
                && !$0.localizedCaseInsensitiveContains("Chose Not To Use")
        }
    }

    /// AO3 rating → a short, glanceable name. Originally scoped to compact cover
    /// cards only (no width for "Teen And Up Audiences" there); list rows and
    /// search-result cards now use the same short form for a consistent stat row.
    static func ratingName(_ rating: String) -> String? {
        switch rating {
        case "General Audiences": "General"
        case "Teen And Up Audiences": "Teen"
        case "Mature": "Mature"
        case "Explicit": "Explicit"
        case "Not Rated": "Not Rated"
        default: rating.isEmpty ? nil : rating
        }
    }

    /// AO3's own single-letter rating shorthand, for the dense four-badge top
    /// row where the spelled-out names don't all fit on one line. Deliberately
    /// NOT used by the compact cover cards: those moved away from cryptic
    /// abbreviations on purpose (see `CoverCardStatsRow` — "the values were
    /// abbreviated to the point of being cryptic") and have the width for the
    /// full name. The icon's color carries the same meaning either way, and the
    /// full rating still reaches VoiceOver through the accessibility label.
    static func ratingLetter(_ rating: String) -> String? {
        switch rating {
        case "General Audiences": "G"
        case "Teen And Up Audiences": "T"
        case "Mature": "M"
        case "Explicit": "E"
        case "Not Rated": "NR"
        default: rating.isEmpty ? nil : rating
        }
    }

    /// AO3's own General/Teen/Mature/Explicit rating-icon color coding, so the
    /// icon carries meaning at a glance instead of every rating looking the same.
    static func ratingColor(_ rating: String) -> Color? {
        switch rating {
        case "General Audiences": .green
        case "Teen And Up Audiences": .yellow
        case "Mature": .orange
        case "Explicit": .red
        // Explicitly gray rather than nil: falling through to `.tint` painted
        // it the app's red accent, which reads as the most severe rating —
        // the opposite of what "no rating given" means. AO3 leaves its own
        // unrated icon blank for the same reason.
        case "Not Rated": .gray
        default: nil
        }
    }

    /// AO3's own category color coding (a small colored badge per
    /// relationship-category tag, e.g. F/F, Gen, Multi). SF Symbols has no
    /// venus/mars/gender glyphs to tell the categories apart by shape, so every
    /// category shares one real SF Symbol ("person.2.fill", same treatment as
    /// the rating shield) and color alone carries the distinction.
    static func categoryColor(_ category: String) -> Color? {
        switch category {
        case "F/F": .red
        case "F/M": .pink
        case "Gen": .green
        case "M/M": .blue
        case "Multi": .purple
        case "Other": .black
        default: nil
        }
    }

    static func categoryAccessibilityLabel(_ category: String) -> String {
        switch category {
        case "F/F": "Category: female/female relationships"
        case "F/M": "Category: female/male relationships"
        case "Gen": "Category: no romantic or sexual relationships, or not the main focus"
        case "M/M": "Category: male/male relationships"
        case "Multi": "Category: more than one kind of relationship"
        case "Other": "Category: other relationships"
        default: "Category: \(category)"
        }
    }

    /// AO3 renders `Published`/`Updated` in two different formats depending on
    /// which page it was scraped from — "2025-11-01" (ISO) on a work's own detail
    /// page (`dd.published`/`dd.status`), "01 Nov 2025" on search/listing blurbs
    /// (`p.datetime`) — both confirmed live against archiveofourown.org. Tries
    /// both, normalizes to MM/DD/YYYY; falls back to the raw string unparsed
    /// rather than showing nothing if AO3 ever changes either format.
    private static let parseFormats = ["yyyy-MM-dd", "dd MMM yyyy"]

    private static let parseFormatters: [DateFormatter] = parseFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    static func displayDate(_ rawText: String) -> String {
        for formatter in parseFormatters {
            if let date = formatter.date(from: rawText) {
                return displayFormatter.string(from: date)
            }
        }
        return rawText
    }
}
