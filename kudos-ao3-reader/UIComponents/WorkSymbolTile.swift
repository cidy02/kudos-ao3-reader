import SwiftUI

/// AO3's own required-tags colours (T-479, decision TILES): the hexes the
/// Symbols board paints its solid tiles in, one palette for all four themes
/// instead of system colours that shift per appearance. Only a tag that is
/// absent, WIP's soft tile and "Other" (which would vanish on a dark page) have
/// a dark-theme step.
enum AO3TagPalette {
    static let general = rgb(0x2F8F3A)
    static let teen = rgb(0xF5C400)
    static let mature = rgb(0xE07000)
    static let explicit = rgb(0xC8102E)
    static let femaleFemale = rgb(0xD2264B)
    static let femaleMale = rgb(0xB3127A)
    static let maleMale = rgb(0x1E63C8)
    static let other = rgb(0x1C1C1E)
    /// #1C1C1E is the Dark theme's own surface and nearly OLED's black.
    static let otherOnDark = rgb(0x48484A)
    /// Teen's glyph: white can't hold contrast on the yellow.
    static let teenInk = rgb(0x3A2C00)
    /// Teen as *text* on a light page, where the tile yellow is ~1.6:1 —
    /// L3-TH-4's dark mustard, kept for that one job.
    static let teenTextOnLight = Color(red: 0.55, green: 0.40, blue: 0)

    /// No warnings, not rated, no category, status unknown: grey, so a typical
    /// row shows two saturated tiles, not four.
    static let absentFill = rgb(0xE6E6EB)
    static let absentInk = rgb(0x6C6C70)
    static let absentFillDark = rgb(0x3A3A3C)
    static let absentInkDark = rgb(0xAEAEB2)

    /// WIP in the board's soft orange — a solid one would be a third orange
    /// "alarm" beside Mature and Not Disclosed. The dark pair keeps it soft
    /// there too, rather than the brightest tile on a black page.
    static let wipFill = rgb(0xFFE6C2)
    static let wipInk = rgb(0xB35A00)
    static let wipFillDark = rgb(0x4A2E0A)
    static let wipInkDark = rgb(0xFFB04D)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// One of a work's four tags as a tile: what it draws and in which colours.
/// Plain data, so the palette and its contrast are testable without a view;
/// `WorkStatusIconGrid` draws it.
///
/// Solid in AO3's colours with a white glyph (Teen: dark on its yellow); the
/// rating is its letter cut out of a shield in the glyph colour, so the letter
/// shows the tile through it.
struct WorkSymbolTile: Equatable {
    enum Mark: Equatable {
        /// The rating letter cut out of a shield.
        case shield(String)
        case gen, femaleFemale, femaleMale, maleMale, other
        /// Four solid quadrants filling the tile; no glyph.
        case multi
        case dash, exclamation, question
        case check, halfRing
    }

    let mark: Mark
    let fill: Color
    let ink: Color

    static func rating(_ rating: String?, dark: Bool) -> WorkSymbolTile {
        switch rating ?? "" {
        case "General Audiences": solid(.shield("G"), AO3TagPalette.general)
        case "Teen And Up Audiences":
            WorkSymbolTile(mark: .shield("T"), fill: AO3TagPalette.teen, ink: AO3TagPalette.teenInk)
        case "Mature": solid(.shield("M"), AO3TagPalette.mature)
        case "Explicit": solid(.shield("E"), AO3TagPalette.explicit)
        // Not Rated, no rating given, or a string AO3 doesn't use.
        default: absent(.shield("?"), dark: dark)
        }
    }

    /// The collapsed card's fold, as `WorkTopStatsRow.topItems` makes it: more
    /// than one recognised category is Multi, none is the grey dash.
    static func category(_ categories: [String], dark: Bool) -> WorkSymbolTile {
        let recognized = categories.filter { WorkStat.categoryColor($0) != nil }
        guard recognized.count == 1, let only = recognized.first else {
            return recognized.isEmpty ? absent(.dash, dark: dark) : multi
        }
        switch only {
        case "F/F": return solid(.femaleFemale, AO3TagPalette.femaleFemale)
        case "F/M": return solid(.femaleMale, AO3TagPalette.femaleMale)
        case "M/M": return solid(.maleMale, AO3TagPalette.maleMale)
        case "Gen": return solid(.gen, AO3TagPalette.general)
        case "Other": return solid(.other, dark ? AO3TagPalette.otherOnDark : AO3TagPalette.other)
        default: return multi // the literal "Multi" tag
        }
    }

    static func warnings(_ status: WorkWarningStatus, dark: Bool) -> WorkSymbolTile {
        switch status {
        case .none: absent(.dash, dark: dark)
        case .undisclosed: solid(.question, AO3TagPalette.mature)
        case .present: solid(.exclamation, AO3TagPalette.explicit)
        }
    }

    static func completion(_ status: WorkCompletionStatus, dark: Bool) -> WorkSymbolTile {
        switch status {
        case .complete: solid(.check, AO3TagPalette.general)
        case .inProgress:
            WorkSymbolTile(
                mark: .halfRing,
                fill: dark ? AO3TagPalette.wipFillDark : AO3TagPalette.wipFill,
                ink: dark ? AO3TagPalette.wipInkDark : AO3TagPalette.wipInk
            )
        case .unknown: absent(.question, dark: dark)
        }
    }

    private static let multi = WorkSymbolTile(mark: .multi, fill: .clear, ink: .clear)

    private static func solid(_ mark: Mark, _ fill: Color) -> WorkSymbolTile {
        WorkSymbolTile(mark: mark, fill: fill, ink: .white)
    }

    private static func absent(_ mark: Mark, dark: Bool) -> WorkSymbolTile {
        dark
            ? WorkSymbolTile(mark: mark, fill: AO3TagPalette.absentFillDark, ink: AO3TagPalette.absentInkDark)
            : WorkSymbolTile(mark: mark, fill: AO3TagPalette.absentFill, ink: AO3TagPalette.absentInk)
    }
}

// MARK: - Drawn marks

extension WorkSymbolTile {
    /// The box every glyph is drawn in, as a fraction of the tile (I-3). The
    /// shield is the one exception, at `shieldBoxRatio`.
    static let glyphBoxRatio: CGFloat = 0.68
    static let shieldBoxRatio: CGFloat = 0.84
    /// Where the rating letter sits in the shield, as a fraction of the
    /// shield's box from its centre: the shield's centroid (y 11.56 of the
    /// board's 24 units) is above its ink centre (12.0) because of the taper,
    /// and the letter centres on the body, not the bounds.
    static let shieldBodyOffset: CGFloat = (11.56 - 12) / 24

    /// `mark` drawn in a `side`-point square, centred on its own ink rather
    /// than on the drawing grid (I-3), so no glyph needs a measured offset. The
    /// typed ⚢ ⚣ ⚤ ♅ ☉ these replace each sat off-centre by a different amount.
    /// Empty for the marks that aren't paths (Multi, "!", "?").
    static func path(for mark: Mark, in side: CGFloat) -> Path {
        // ponytail: rebuilt per render (a few boolean ops per tile); cache per mark if a list ever profiles slow.
        let ink = outline(mark)
        guard !ink.isEmpty else { return ink }
        let bounds = ink.cgPath.boundingBoxOfPath
        let scale = side / 24
        return ink.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: side / 2 - bounds.midX * scale,
            ty: side / 2 - bounds.midY * scale
        ))
    }

    /// The mark on the Symbols board's 24-unit grid, as one filled outline.
    /// The shield, check, Gen and WIP ring are the board's own geometry; the
    /// four category signs are drawn here to the same stroke and extent, after
    /// the Apple Symbols glyphs the board typed.
    private static func outline(_ mark: Mark) -> Path {
        switch mark {
        case .shield:
            var shield = Path()
            shield.move(to: CGPoint(x: 12, y: 2.6))
            shield.addLine(to: CGPoint(x: 4.4, y: 5.5))
            shield.addLine(to: CGPoint(x: 4.4, y: 11.5))
            shield.addCurve(to: CGPoint(x: 12, y: 21.4),
                            control1: CGPoint(x: 4.4, y: 16.2), control2: CGPoint(x: 7.6, y: 20.1))
            shield.addCurve(to: CGPoint(x: 19.6, y: 11.5),
                            control1: CGPoint(x: 16.4, y: 20.1), control2: CGPoint(x: 19.6, y: 16.2))
            shield.addLine(to: CGPoint(x: 19.6, y: 5.5))
            shield.closeSubpath()
            // Filled and stroked 1.4 with round joins, which softens its three points.
            return shield.union(shield.strokedPath(StrokeStyle(lineWidth: 1.4, lineJoin: .round)))
        case .check:
            return stroked([polyline((5, 12.5), (9.6, 17.1), (19.2, 7.4))], width: 3.4)
        case .halfRing:
            let ring = stroked([circle(12, 12, 8.2)], width: 2.6)
            let leftHalf = circle(12, 12, 8.2).intersection(Path(CGRect(x: 0, y: 0, width: 12, height: 24)))
            return ring.union(leftHalf)
        case .gen:
            return stroked([circle(12, 12, 8)], width: 2.4).union(circle(12, 12, 2.6))
        case .dash:
            // The board's bar: 42% of the tile wide, 11% tall, fully rounded.
            return stroked([polyline((6.53, 12), (17.47, 12))], width: 3.88)
        case .femaleFemale:
            // ⚢: two linked rings; one crossbar through both stems, as Apple
            // Symbols draws it, rather than two that all but touch.
            return stroked([
                circle(8, 8.4, 4.8), polyline((8, 13.2), (8, 18.8)),
                circle(16, 8.4, 4.8), polyline((16, 13.2), (16, 18.8)),
                polyline((5.4, 16), (18.6, 16)),
            ], width: signStroke)
        case .femaleMale:
            // ⚤: the rings linked on a diagonal, cross down and arrow up-right.
            return stroked([
                circle(9.2, 13.4, 4.4), polyline((9.2, 17.8), (9.2, 22)), polyline((6.6, 20), (11.8, 20)),
            ], width: signStroke)
                .union(maleSign(CGPoint(x: 13.9, y: 8.7), radius: 4.4, arrow: 3.8, head: 3.4))
        case .maleMale:
            // ⚣: offset along the diagonal so each arrow clears the other ring.
            return maleSign(CGPoint(x: 7.6, y: 11.2), radius: 4.8, arrow: 4.6, head: 3.6)
                .union(maleSign(CGPoint(x: 13, y: 16.6), radius: 4.8, arrow: 4.6, head: 3.6))
        case .other:
            // ♅: a bracketed H whose centre stem drops to a small ring.
            return stroked([
                polyline((3.6, 3.6), (5.8, 3.6), (5.8, 14.4), (3.6, 14.4)),
                polyline((20.4, 3.6), (18.2, 3.6), (18.2, 14.4), (20.4, 14.4)),
                polyline((5.8, 9), (18.2, 9)),
                polyline((12, 3.6), (12, 16)),
                circle(12, 18.9, 2.9),
            ], width: signStroke)
        case .multi, .exclamation, .question:
            return Path()
        }
    }

    private static let signStroke: CGFloat = 2.2

    /// ♂ with its arrow at 45° up-right; the head is mitred so it ends in a point.
    private static func maleSign(_ center: CGPoint, radius: CGFloat, arrow: CGFloat, head: CGFloat) -> Path {
        let diagonal = CGFloat(0.5).squareRoot()
        let tip = CGPoint(x: center.x + (radius + arrow) * diagonal, y: center.y - (radius + arrow) * diagonal)
        let shaft = polyline((center.x + radius * diagonal, center.y - radius * diagonal), (tip.x, tip.y))
        let chevron = polyline((tip.x - head, tip.y), (tip.x, tip.y), (tip.x, tip.y + head))
        return stroked([circle(center.x, center.y, radius), shaft], width: signStroke)
            .union(chevron.strokedPath(StrokeStyle(lineWidth: signStroke, lineCap: .round, lineJoin: .miter)))
    }

    /// Each piece stroked on its own, then unioned: stroking overlapping
    /// subpaths together can leave their overlaps unfilled.
    private static func stroked(_ pieces: [Path], width: CGFloat) -> Path {
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        return pieces.reduce(Path()) { $0.union($1.strokedPath(style)) }
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    private static func polyline(_ points: (CGFloat, CGFloat)...) -> Path {
        var path = Path()
        path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        return path
    }
}
