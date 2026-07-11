import Foundation
import SwiftUI

/// How the reader lays out a chapter.
enum ReadingMode: String, CaseIterable, Identifiable {
    case scroll, paged
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .scroll: "Scrolled"
        case .paged: "Paged"
        }
    }

    var symbol: String {
        switch self {
        case .scroll: "scroll"
        case .paged: "book.pages"
        }
    }
}

/// A reading color theme applied to the EPUB content.
enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark, oled
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .light: "Light"
        case .sepia: "Sepia"
        case .dark: "Dark"
        case .oled: "OLED"
        }
    }

    var symbol: String {
        switch self {
        case .light: "sun.max"
        case .sepia: "book.closed"
        case .dark: "moon"
        case .oled: "moon.stars.fill"
        }
    }

    /// CSS hex for the page background.
    var backgroundHex: String {
        switch self {
        case .light: "#FFFFFF"
        case .sepia: "#FBF0D9"
        case .dark: "#16161A"
        case .oled: "#000000"
        }
    }

    /// CSS hex for body text.
    var textHex: String {
        switch self {
        case .light: "#1E1E1E"
        case .sepia: "#5B4636"
        case .dark, .oled: "#CFCFD4"
        }
    }

    /// CSS hex for links.
    var linkHex: String {
        switch self {
        case .light: "#0B66C2"
        case .sepia: "#8A5A2B"
        case .dark, .oled: "#7FB0E8"
        }
    }

    /// SwiftUI color matching `backgroundHex`, for the area around the web content.
    /// The app shell's `appBaseBackground` reuses this exact token for Dark/OLED
    /// rather than restating the RGB values, so the app and the reader can never
    /// drift apart into two different "dark backgrounds".
    var backgroundColor: Color {
        switch self {
        case .light: Color(white: 1.0)
        case .sepia: Color(red: 0.984, green: 0.941, blue: 0.851)
        case .dark: Color(red: 0.086, green: 0.086, blue: 0.105)
        case .oled: .black
        }
    }

    /// SwiftUI color matching `textHex`, used by the theme swatches' sample glyph.
    var textColor: Color {
        switch self {
        case .light: Color(red: 0.118, green: 0.118, blue: 0.118)
        case .sepia: Color(red: 0.357, green: 0.275, blue: 0.212)
        case .dark, .oled: Color(red: 0.812, green: 0.812, blue: 0.831)
        }
    }

    /// The system color scheme this theme maps to, so SwiftUI chrome (sheets, Liquid
    /// Glass, navigation bars) adapts with the theme. Sepia is a warm light scheme;
    /// OLED is still a `.dark` scheme (just with its own true-black surfaces below).
    var colorScheme: ColorScheme {
        switch self {
        case .light, .sepia: .light
        case .dark, .oled: .dark
        }
    }

    // MARK: App-wide surface colours

    // Every non-Light theme substitutes its own app-wide surfaces here — this is the
    // one place that decides them, so every List/Form/scene background in the app
    // (via `.appThemedScroll()`/`.appThemedRows()`/`.cardList()`, or a direct
    // `appBaseBackground ?? …` fallback) reads them instead of scattering its own
    // per-theme checks. Sepia warms the system's neutral surfaces since the system
    // has no sepia scheme; Dark swaps the system's near-black default for the exact
    // `backgroundColor` above so the app shell and the reader never disagree; OLED
    // goes to true black. Light alone keeps the native system surfaces (`nil`).

    /// The recessed base behind grouped content (≈ `systemGroupedBackground`) — the
    /// screen's main background.
    var appBaseBackground: Color? {
        switch self {
        case .light: nil
        case .sepia: Color(red: 0.925, green: 0.871, blue: 0.757)
        case .dark: backgroundColor
        case .oled: .black
        }
    }

    /// Raised surfaces — list/form cells, bars, popovers (≈ `secondarySystemGroupedBackground`).
    /// Kept a visible step above `appBaseBackground` in both Dark and OLED so cards
    /// stay readable against their (very dark, or true-black) backdrop.
    var appElevatedBackground: Color? {
        switch self {
        case .light: nil
        case .sepia: Color(red: 0.984, green: 0.941, blue: 0.851)
        case .dark: Color(red: 0.133, green: 0.133, blue: 0.157)
        case .oled: Color(red: 0.110, green: 0.110, blue: 0.118)
        }
    }

    /// Accent/tint for controls, links, and selection.
    var appTint: Color? {
        self == .sepia ? Color(red: 0.604, green: 0.404, blue: 0.196) : nil
    }

    /// Hairline separators and borders that read on the warm surfaces.
    var appSeparator: Color? {
        self == .sepia ? Color(red: 0.357, green: 0.275, blue: 0.212).opacity(0.18) : nil
    }
}

/// A font choice in the reader: either a bundled system family or an imported font.
struct ReaderFontOption: Identifiable {
    let id: String
    let name: String
    /// The CSS `font-family` value to apply.
    let cssFamily: String
    /// For imported fonts, the on-disk file to embed via `@font-face`.
    let customFileURL: URL?

    var isCustom: Bool {
        customFileURL != nil
    }

    /// Built-in families available on Apple platforms.
    static let builtIns: [ReaderFontOption] = [
        .init(
            id: "system",
            name: "System",
            cssFamily: "-apple-system, system-ui, sans-serif",
            customFileURL: nil
        ),
        .init(
            id: "nyserif",
            name: "New York",
            cssFamily: "'New York', ui-serif, Georgia, serif",
            customFileURL: nil
        ),
        .init(id: "georgia", name: "Georgia", cssFamily: "Georgia, serif", customFileURL: nil),
        .init(
            id: "palatino",
            name: "Palatino",
            cssFamily: "'Palatino Linotype', Palatino, 'Book Antiqua', serif",
            customFileURL: nil
        ),
        .init(id: "times", name: "Times New Roman", cssFamily: "'Times New Roman', Times, serif", customFileURL: nil),
        .init(
            id: "helvetica",
            name: "Helvetica Neue",
            cssFamily: "'Helvetica Neue', Helvetica, Arial, sans-serif",
            customFileURL: nil
        ),
        .init(id: "avenir", name: "Avenir", cssFamily: "'Avenir Next', Avenir, sans-serif", customFileURL: nil),
        .init(id: "menlo", name: "Menlo", cssFamily: "Menlo, ui-monospace, monospace", customFileURL: nil)
    ]

    /// All selectable fonts: the built-ins followed by the user's imported fonts.
    /// Shared by the reader and Settings so both show an identical list.
    static func options(customFonts: [CustomFont]) -> [ReaderFontOption] {
        builtIns + customFonts.map {
            ReaderFontOption(id: $0.selectionID, name: $0.name, cssFamily: "serif", customFileURL: $0.fileURL)
        }
    }

    /// The font matching `id`, falling back to the system default.
    static func current(id: String, customFonts: [CustomFont]) -> ReaderFontOption {
        options(customFonts: customFonts).first { $0.id == id } ?? builtIns[0]
    }
}

/// The reader's custom typography settings (Apple Books–style "Customize Theme").
/// `bold` and the chosen font always apply; the layout options (spacing, margins,
/// justify) only take effect while `customize` is on, mirroring Apple Books' master
/// toggle. `resolved` folds that rule in so callers can build CSS unconditionally.
struct ReaderTextStyle: Equatable {
    var customize: Bool = false
    var bold: Bool = false
    /// Body text size in points. Emitted as CSS `px`, which equals points under the
    /// device-width viewport the reader injects. Always applies, independent of the
    /// Customize master toggle.
    var fontSizePt: Double = defaultFontSizePt
    /// CSS `line-height` multiplier.
    var lineHeight: Double = defaultLineHeight
    /// CSS `letter-spacing`, in em.
    var letterSpacing: Double = 0
    /// CSS `word-spacing`, in em.
    var wordSpacing: Double = 0
    /// Horizontal page margin, in points/px (shared by scrolled and paged modes).
    var margin: Double = defaultMargin
    var justify: Bool = false

    static let defaultLineHeight = 1.65
    /// Comfortable horizontal breathing room from the screen edges (px). Now that the
    /// reader injects a device-width viewport, this renders at its true size.
    static let defaultMargin: Double = 28

    // Slider bounds, kept here so the reader CSS and the Customize sheet agree.
    static let defaultFontSizePt: Double = 18
    static let fontSizeRange = 12.0 ... 34.0
    static let fontSizeStep = 1.0
    static let lineHeightRange = 1.2 ... 2.4
    static let letterSpacingRange = -0.03 ... 0.12
    static let wordSpacingRange = 0.0 ... 0.6
    static let marginRange = 8.0 ... 64.0

    /// The effective style: when Customize is off, layout options fall back to the
    /// defaults while the always-on font weight and text size are preserved.
    var resolved: ReaderTextStyle {
        guard !customize else { return self }
        return ReaderTextStyle(
            customize: false, bold: bold, fontSizePt: fontSizePt,
            lineHeight: Self.defaultLineHeight, letterSpacing: 0, wordSpacing: 0,
            margin: Self.defaultMargin, justify: false
        )
    }

    /// A compact identity used to detect when a re-layout is needed.
    var token: String {
        [
            customize ? "1" : "0",
            bold ? "1" : "0",
            "\(fontSizePt)",
            "\(lineHeight)",
            "\(letterSpacing)",
            "\(wordSpacing)",
            "\(margin)",
            justify ? "1" : "0"
        ].joined(separator: "|")
    }
}

/// Builds the stylesheet injected into the reader's web view for the current settings.
enum ReaderStylesheet {
    static func css(theme: ReaderTheme, font: ReaderFontOption, style: ReaderTextStyle = ReaderTextStyle()) -> String {
        var fontFace = ""
        var family = font.cssFamily

        if let url = font.customFileURL, let data = try? Data(contentsOf: url) {
            let base64 = data.base64EncodedString()
            let format = url.pathExtension.lowercased() == "otf" ? "opentype" : "truetype"
            let mime = url.pathExtension.lowercased() == "otf" ? "font/otf" : "font/ttf"
            fontFace = """
            @font-face { font-family: 'ReaderUserFont'; font-display: swap; \
            src: url(data:\(mime);base64,\(base64)) format('\(format)'); }
            """
            family = "'ReaderUserFont', \(font.cssFamily)"
        }

        let resolvedStyle = style.resolved

        // Optional rules are emitted only when they actually change something, so a
        // non-customized reader produces the same CSS as before (this keeps macOS and
        // the default iOS look untouched, and never overrides an EPUB's own alignment
        // or letter-spacing unless the user asked for it).
        let blockSelectors = "body, p, div, li, blockquote, td, th"
        var blockRules = ""
        if resolvedStyle.justify {
            blockRules += "text-align: justify !important; -webkit-hyphens: auto; hyphens: auto;"
        }
        if resolvedStyle.letterSpacing != 0 {
            blockRules += "letter-spacing: \(resolvedStyle.letterSpacing)em !important;"
        }
        if resolvedStyle.wordSpacing != 0 {
            blockRules += "word-spacing: \(resolvedStyle.wordSpacing)em !important;"
        }
        let blockRule = blockRules.isEmpty ? "" : "\(blockSelectors) { \(blockRules) }"

        // Bold is applied via !important so an EPUB's own `font-weight: normal` on
        // paragraphs can't win; headings and <strong> keep their own heavier weight.
        let boldRule = resolvedStyle.bold
            ? "p, div, span, li, blockquote, td, th, a { font-weight: 600 !important; }"
            : ""

        // Absolute body text size in px (== points under the injected device-width
        // viewport), set by the Text Size control.
        let fontSize = Int(resolvedStyle.fontSizePt.rounded())
        let marginPx = Int(resolvedStyle.margin)

        return """
        \(fontFace)
        html, body {
            background-color: \(theme.backgroundHex) !important;
            color: \(theme.textHex) !important;
        }
        body {
            font-family: \(family) !important;
            line-height: \(resolvedStyle.lineHeight);
            /* !important so the Text Size scale beats calibre EPUBs' `.calibre`
               class rule on <body> (a class selector outranks `body` on specificity,
               which otherwise pins the size to 1em and ignores the setting). The
               paged layout never sets font-size inline, so there's no conflict. */
            font-size: \(fontSize)px !important;
            max-width: 42em;
            margin: 0 auto;
            /* The layout script overrides the top/bottom padding with the device's
               fixed safe-area insets (the web view runs full-screen); this is the
               base used before the script runs. */
            padding: 1.4em \(marginPx)px 7em;
            -webkit-text-size-adjust: 100%;
        }
        /* Beat calibre EPUBs' `.calibre { padding-left/right: 0; margin: 0 5pt }` — a
           class selector outranks `body`, which otherwise pins the Margins setting to
           zero in scrolled mode. `body[class]` (0,1,1) wins over `.calibre` (0,1,0),
           and it's not !important, so the paged layout's inline padding still wins. */
        body[class] {
            padding-left: \(marginPx)px;
            padding-right: \(marginPx)px;
            margin-left: auto;
            margin-right: auto;
        }
        p, div, span, li, h1, h2, h3, h4, h5, h6, blockquote, td, th, em, strong, a {
            color: \(theme.textHex) !important;
            font-family: \(family) !important;
            /* Only break a "word" when it can't fit on a line by itself (long URLs),
               so the content can't overflow horizontally. `overflow-wrap: break-word`
               leaves normal words intact — unlike `word-break`, which split words
               mid-character as a side effect. */
            overflow-wrap: break-word;
        }
        \(blockRule)
        \(boldRule)
        a { color: \(theme.linkHex) !important; text-decoration: none; }
        img, svg { max-width: 100% !important; height: auto !important; }
        hr { border-color: \(theme.textHex); opacity: 0.25; }
        """
    }

    // Lint: existing JS bridge stays cohesive for behavior stability.
    /// JavaScript that installs the theme `<style>` and lays the chapter out for the
    /// given mode. In paged mode it builds CSS columns (`columns` per screen) and
    /// exposes `readerStep`/`readerLast` so the host can turn pages and detect
    /// chapter boundaries.
    static func layoutScript( // swiftlint:disable:this function_body_length
        css: String,
        mode: ReadingMode,
        columns: Int,
        margin: Int = 28,
        safeTop: Int = 0,
        safeBottom: Int = 0
    ) -> String {
        let base64 = Data(css.utf8).base64EncodedString()
        let modeJS = mode == .paged ? "paged" : "scroll"
        return """
        (function() {
            // AO3's calibre EPUBs ship no viewport meta, so WebKit lays them out at a
            // ~980px default width and scales that down to the screen — shrinking all
            // text to ~40%. Force a device-width viewport so text renders at its true
            // size (and `px` == points), which is what the Text Size control assumes.
            (function() {
                var vp = document.querySelector('meta[name=viewport]');
                if (!vp) {
                    vp = document.createElement('meta');
                    vp.setAttribute('name', 'viewport');
                    document.head.appendChild(vp);
                }
                // viewport-fit=cover exposes env(safe-area-inset-*) so the content can
                // pad itself away from the notch / home indicator. The web view fills
                // the whole screen (so toggling the chrome never resizes it and the
                // paged layout stays put); the padding keeps text out of the unsafe areas.
                vp.setAttribute('content', 'width=device-width, initial-scale=1, viewport-fit=cover');
            })();

            var id = 'reader-theme-style';
            var st = document.getElementById(id);
            if (!st) { st = document.createElement('style'); st.id = id; document.head.appendChild(st); }
            st.textContent = atob('\(base64)');

            // Some EPUBs (calibre exports of AO3 works) double-encode entities, so
            // a chapter title arrives as the literal text "Rayanne &amp; Lizzy".
            // Decode those leftovers in headings, where they're plainly artifacts.
            (function() {
                var map = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'" };
                var hs = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                for (var i = 0; i < hs.length; i++) {
                    if (hs[i].childElementCount !== 0) continue;
                    var t = hs[i].textContent;
                    var u = t.replace(/&(amp|lt|gt|quot|#39|apos);/g, function(m) { return map[m]; });
                    if (u !== t) hs[i].textContent = u;
                }
            })();

            var MODE = '\(modeJS)', COLS = \(columns), M = \(margin);
            // Fixed device safe-area insets (notch / home indicator), passed from the
            // host. Constant regardless of the chrome, so the content never shifts when
            // the nav bar or chapter pill toggle (unlike CSS env(), which grows with
            // the nav bar).
            var ST = \(safeTop), SB = \(safeBottom);
            window.__mode = MODE;
            var b = document.body, de = document.documentElement;

            function clear() {
                ['height','columnWidth','columnGap','columnFill','overflow','overflowX','transform',
                 'paddingLeft','paddingRight','paddingTop','paddingBottom','margin','maxWidth','width','boxSizing']
                    .forEach(function(p) { b.style[p] = ''; });
                de.style.height = ''; de.style.overflow = ''; de.style.overflowX = '';
                b.scrollLeft = 0;
            }
            function count() { return Math.max(1, Math.round(b.scrollWidth / window.innerWidth)); }
            function post() {
                var info = (MODE === 'paged')
                    ? { mode: 'paged', page: (window.__page || 0) + 1, total: count() }
                    : { mode: 'scroll' };
                try { window.webkit.messageHandlers.reader.postMessage(info); } catch (e) {}
            }
            function relayout(animate) {
                var W = window.innerWidth, total = count();
                if (window.__page > total - 1) window.__page = total - 1;
                if (window.__page < 0) window.__page = 0;
                // Page by scrolling the column container, NOT by translating it.
                // A `translateX(-page*W)` on a body whose scrollWidth grows with the
                // chapter length builds an enormous compositing layer; past a certain
                // extent WebKit stops painting its tiles and pages render blank. Native
                // scroll only tiles content near the offset, so long works stay solid.
                var x = (window.__page || 0) * W;
                // Animate page turns (Apple Books–style slide); jump instantly for
                // initial layout / resize. A retargeting smooth scroll absorbs fast
                // swipes without the double-column flash a hard jump produced.
                if (animate && b.scrollTo) {
                    try { b.scrollTo({ left: x, behavior: 'smooth' }); }
                    catch (e) { b.scrollLeft = x; }
                } else {
                    b.scrollLeft = x;
                }
                post();
            }
            function applyPaged() {
                clear();
                var W = window.innerWidth, H = window.innerHeight;
                de.style.height = '100%'; de.style.overflow = 'hidden';
                b.style.boxSizing = 'border-box';
                b.style.margin = '0';
                b.style.maxWidth = 'none';
                b.style.height = H + 'px';
                // Pad past the notch / home indicator (the web view runs full-screen
                // under them). The bottom also reserves room for the floating chapter
                // pill, so padding stays identical whether the chrome is shown or not.
                b.style.paddingTop = (M + ST) + 'px';
                b.style.paddingBottom = (M + 40 + SB) + 'px';
                // Symmetric horizontal padding is essential: it makes the content box
                // exactly (W - 2M), which equals COLS columns plus their gaps. With an
                // asymmetric padding the box is wider than the columns, so the browser
                // stretches the single column to fill it — the real page stride becomes
                // W + M while we scroll by W, and that ~M/page drift compounds until late
                // pages scroll past the content and render blank.
                b.style.paddingLeft = M + 'px';
                b.style.paddingRight = M + 'px';
                b.style.columnGap = (2 * M) + 'px';
                b.style.columnWidth = ((W - 2 * M * COLS) / COLS) + 'px';
                b.style.columnFill = 'auto';
                b.style.overflow = 'hidden';
                if (typeof window.__page !== 'number') window.__page = 0;
                relayout(false);
            }
            function applyScroll() {
                clear();
                de.style.height = 'auto';
                // Vertical scroll only — block horizontal scroll so the chapter-change
                // swipe can't drag the page sideways.
                de.style.overflowX = 'hidden';
                b.style.overflowX = 'hidden';
                window.__page = 0;
                // Fixed safe-area top/bottom padding (full-screen web view), so the
                // content doesn't shift when the chrome toggles.
                b.style.paddingTop = 'calc(1.4em + ' + ST + 'px)';
                b.style.paddingBottom = 'calc(7em + ' + SB + 'px)';
                post();
            }

            window.readerApply = function() { if (MODE === 'paged') applyPaged(); else applyScroll(); };
            window.readerStep = function(d) {
                if (MODE !== 'paged') return 'na';
                var total = count(), p = (window.__page || 0) + d;
                if (p < 0) return 'start';
                if (p > total - 1) return 'end';
                window.__page = p; relayout(true); return 'moved';
            };
            window.readerLast = function() { if (MODE === 'paged') { window.__page = count() - 1; relayout(false); } };

            if (!window.__readerResize) {
                window.__readerResize = true;
                window.addEventListener('resize', function() {
                    if (window.__mode === 'paged') window.readerApply();
                });
            }
            if (!window.__readerScroll) {
                window.__readerScroll = true;
                window.addEventListener('scroll', function() {
                    if (window.__mode !== 'scroll') return;
                    var doc = document.documentElement;
                    var atBottom = (window.innerHeight + window.scrollY) >= (doc.scrollHeight - 4);
                    if (atBottom && !window.__atBottom) {
                        window.__atBottom = true;
                        try { window.webkit.messageHandlers.reader.postMessage({ event: 'bottom' }); } catch (e) {}
                    } else if (!atBottom) {
                        window.__atBottom = false;
                    }
                }, { passive: true });
            }
            if (!window.__readerKeys) {
                window.__readerKeys = true;
                document.addEventListener('keydown', function(e) {
                    if (window.__mode !== 'paged') return;
                    if (e.key === 'ArrowRight' || e.key === 'ArrowLeft' || e.key === ' ') {
                        e.preventDefault();
                        try { window.webkit.messageHandlers.reader.postMessage({ key: e.key }); } catch (_) {}
                    }
                });
            }
            window.readerApply();
            return 'ok';
        })();
        """
    }
}
