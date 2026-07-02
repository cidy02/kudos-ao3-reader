#if os(iOS)
import SwiftUI
import SwiftData
import WebKit

/// An Apple Books–style "Customize Theme" sheet (iOS only). A live sample at the
/// top reflects every change in real time; below it are the text controls (font,
/// bold) and the accessibility/layout options gated by a master "Customize" toggle.
/// All values persist via `@AppStorage` and feed the same CSS the reader injects,
/// so what you see here is exactly what the reader renders.
struct CustomizeThemeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]

    /// The reader's effective theme (mirrors the app theme while linked). Selecting a
    /// swatch writes through here, so when linked it re-themes the whole app too.
    private var theme: ReaderTheme { themeManager.readerTheme }

    @AppStorage("readerFontID") private var fontID: String = "system"
    @AppStorage("readerCustomize") private var customize = false
    @AppStorage("readerBoldText") private var boldText = false
    @AppStorage("readerFontPt") private var fontSizePt: Double = ReaderTextStyle.defaultFontSizePt
    @AppStorage("readerLineHeight") private var lineHeight: Double = ReaderTextStyle.defaultLineHeight
    @AppStorage("readerLetterSpacing") private var letterSpacing: Double = 0
    @AppStorage("readerWordSpacing") private var wordSpacing: Double = 0
    @AppStorage("readerMargin") private var pageMargin: Double = ReaderTextStyle.defaultMargin
    @AppStorage("readerJustify") private var justify = false

    /// Readium accepts only non-negative letter spacing. Keep this branch's iOS
    /// control honest instead of displaying values the navigator must clamp.
    private let supportedLetterSpacingRange = 0.0...ReaderTextStyle.letterSpacingRange.upperBound

    /// The sheet's full height, so the preview can scale to a generous fraction of it.
    @State private var sheetHeight: CGFloat = 0

    private var fontOptions: [ReaderFontOption] {
        ReaderFontOption.options(customFonts: customFonts)
    }
    private var currentFont: ReaderFontOption {
        ReaderFontOption.current(id: fontID, customFonts: customFonts)
    }
    private var style: ReaderTextStyle {
        ReaderTextStyle(
            customize: customize, bold: boldText, fontSizePt: fontSizePt,
            lineHeight: lineHeight, letterSpacing: letterSpacing, wordSpacing: wordSpacing,
            margin: pageMargin, justify: justify
        )
    }
    private var css: String { ReaderStylesheet.css(theme: theme, font: currentFont, style: style) }

    var body: some View {
        NavigationStack {
            Form {
              // Group so .appThemedRows() reaches every section's rows — it doesn't
              // propagate from the Form container, only from a Group/Section/ForEach.
              Group {
                Section("Text") {
                    Picker("Font", selection: $fontID) {
                        ForEach(fontOptions) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.navigationLink)

                    Toggle("Bold Text", isOn: $boldText)
                }

                Section {
                    Toggle("Customize", isOn: $customize.animation(.easeInOut(duration: 0.2)))

                    Group {
                        sliderRow("Line Spacing", icon: "arrow.up.and.down.text.horizontal",
                                  value: $lineHeight, range: ReaderTextStyle.lineHeightRange,
                                  valueLabel: String(format: "%.2f", lineHeight))
                        sliderRow("Character Spacing", icon: "textformat.abc",
                                  value: $letterSpacing, range: supportedLetterSpacingRange)
                        sliderRow("Word Spacing", icon: "line.3.horizontal",
                                  value: $wordSpacing, range: ReaderTextStyle.wordSpacingRange)
                        sliderRow("Margins", icon: "rectangle.inset.filled",
                                  value: $pageMargin, range: ReaderTextStyle.marginRange)
                        Toggle("Justify Text", isOn: $justify)
                    }
                    .disabled(!customize)
                } header: {
                    Text("Accessibility & Layout")
                } footer: {
                    Text("When Customize is off, the reader uses comfortable defaults. "
                         + "Bold Text and the font apply either way.")
                }

                Section {
                    Button(role: .destructive, action: reset) {
                        Label("Reset Theme", systemImage: "arrow.counterclockwise")
                    }
                }
              }
              .appThemedRows()
            }
            .safeAreaInset(edge: .top) { previewHeader }
            .appThemedScroll()
            .navigationTitle("Customize Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Measure the full sheet so the preview can size to a device-responsive
        // fraction of it (independent of the inset, so there's no layout feedback).
        .background {
            Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
        }
        // The sheet's chrome (Liquid Glass, grouped backgrounds, controls) follows
        // the selected reader theme — dark in Dark, light in Light/Sepia.
        .preferredColorScheme(theme.colorScheme)
    }

    // MARK: Pinned live preview + theme swatches

    private var previewHeader: some View {
        // A large, device-responsive preview so several lines of sample text are
        // visible at once; clamped to stay sensible on small and large screens.
        let previewHeight = min(max(sheetHeight * 0.42, 240), 380)
        return VStack(spacing: 14) {
            ThemePreview(css: css)
                .frame(height: previewHeight)
                .background(theme.backgroundColor)
                // Fade the last lines into the page colour so longer samples read as
                // continuing rather than being abruptly cut at the bottom edge.
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [theme.backgroundColor.opacity(0), theme.backgroundColor],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 36)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

            HStack(spacing: 12) {
                ForEach(ReaderTheme.allCases) { swatch($0) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        // Warm base under Sepia (matches the themed Form); system grouped otherwise.
        .background(themeManager.appTheme.appBaseBackground ?? Color(.systemGroupedBackground))
    }

    private func swatch(_ option: ReaderTheme) -> some View {
        let selected = option == theme
        return Button {
            themeManager.readerTheme = option
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(option.backgroundColor)
                    Text("Aa")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(option.textColor)
                }
                .frame(width: 54, height: 54)
                .overlay {
                    Circle().strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: selected ? 3 : 1
                    )
                }
                Text(option.title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sliders

    /// A labelled slider, Apple Books–style: a descriptive icon and title on top
    /// (with an optional value readout, e.g. Line Spacing "1.45"), slider below.
    private func sliderRow(_ title: String, icon: String, value: Binding<Double>,
                           range: ClosedRange<Double>, valueLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline)
                Spacer()
                if let valueLabel {
                    Text(valueLabel)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(customize ? .primary : .secondary)
            Slider(value: value, in: range)
        }
        .padding(.vertical, 2)
    }

    private func reset() {
        // Text Size is a separate primary control now, so Reset Theme leaves it alone.
        withAnimation(.easeInOut(duration: 0.2)) {
            customize = false
            boldText = false
            fontID = "system"
            lineHeight = ReaderTextStyle.defaultLineHeight
            letterSpacing = 0
            wordSpacing = 0
            pageMargin = ReaderTextStyle.defaultMargin
            justify = false
        }
    }
}

// MARK: - Live preview web view

/// A small WKWebView that renders sample prose with the reader's stylesheet, so the
/// preview matches the real reader exactly — including justification, word spacing
/// and margins that SwiftUI's `Text` can't reproduce. CSS is swapped in place (no
/// reloads) as settings change.
private struct ThemePreview: UIViewRepresentable {
    let css: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.pendingCSS = css
        web.loadHTMLString(Self.sampleHTML, baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.apply(css, to: web)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var pendingCSS: String?
        private var loaded = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let css = pendingCSS { inject(css, into: webView) }
        }

        func apply(_ css: String, to web: WKWebView) {
            pendingCSS = css
            if loaded { inject(css, into: web) }
        }

        private func inject(_ css: String, into web: WKWebView) {
            // Trim only the reader's tall vertical padding so the sample fills the
            // card — leave the horizontal padding alone so the Margins slider shows.
            // Trim the reader's tall vertical padding AND the first element's top
            // margin (the sample's <h3>) so the preview starts snug at the top —
            // space is precious here with all the options below.
            let preview = css
                + "\nhtml, body { height: auto !important; } "
                + "body { padding-top: 0.5em !important; padding-bottom: 0.7em !important; } "
                + "body > *:first-child { margin-top: 0 !important; }"
            let base64 = Data(preview.utf8).base64EncodedString()
            web.evaluateJavaScript("""
            (function(){var id='preview-style';var s=document.getElementById(id);
            if(!s){s=document.createElement('style');s.id=id;document.head.appendChild(s);}
            s.textContent=atob('\(base64)');})();
            """)
        }
    }

    private static let sampleHTML = """
    <!doctype html>
    <html lang="en"><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    </head><body>
    <h3>A Study in Starlight</h3>
    <p>The lantern guttered as she turned the final page, and for a moment the whole
    library seemed to lean in to listen.</p>
    <p>Outside, the rain had softened to a whisper against the glass — patient and
    unhurried, the way the best stories always are.</p>
    <p>She traced the last line with one finger, unwilling to let it end, and wondered
    how many readers before her had paused in exactly this place.</p>
    <p>Somewhere a clock counted the small hours. The words stayed with her, warm as a
    held breath, long after the candle had burned low.</p>
    <p>When at last she rose, the room felt larger than before — as though the story had
    quietly made room for one more.</p>
    </body></html>
    """
}
#endif
