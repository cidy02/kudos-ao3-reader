import Foundation

/// Scoped, strict-XHTML-safe stylesheet for the in-chapter end-of-chapter card
/// (`#kudos-chapter-end`, T-578). Kept free of `<`, `>`, and `&` so XML parsers
/// serving `application/xhtml+xml` never reject the `<style>` element.
nonisolated enum ReaderChapterEndStylesheet {
    static func stylesheet(
        style: ReaderChapterEndStyle,
        noteMatch: ReaderChapterEndFacts.EndNoteMatch?
    ) -> String {
        let accent = safeCSSColor(style.accentHex, fallback: "#821019")
        let label = safeCSSColor(style.accentLabelHex, fallback: "#FFFFFF")
        let lightInk = safeCSSColor(style.lightAccentInkHex, fallback: accent)
        let sepiaInk = safeCSSColor(style.sepiaAccentInkHex, fallback: accent)
        let darkInk = safeCSSColor(style.darkAccentInkHex, fallback: "#EE8A93")

        var rules = ""
        if let noteMatch {
            if noteMatch.isConvertedAside {
                rules += "aside.author-note:last-of-type { display: none !important; }\n"
            } else {
                rules += "[id^=\"endnotes\"], div.end.notes, div.endnotes { display: none !important; }\n"
            }
        }
        rules += themeVariablesCSS(
            accent: accent, label: label, lightInk: lightInk,
            sepiaInk: sepiaInk, darkInk: darkInk
        )
        rules += ruleCSS
        rules += noteCSS
        rules += nextButtonCSS
        rules += actionsAndFooterCSS
        return rules
    }

    static func safeCSSColor(_ hex: String, fallback: String) -> String {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6,
              trimmed.allSatisfy(\.isHexDigit)
        else { return fallback }
        return "#\(trimmed)"
    }

    private static func themeVariablesCSS(
        accent: String,
        label: String,
        lightInk: String,
        sepiaInk: String,
        darkInk: String
    ) -> String {
        let anchorID = ReaderChapterEndHTML.anchorID
        let sectionID = ReaderChapterEndHTML.sectionID
        let uiFont = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", system-ui, sans-serif"
        return """
        #\(anchorID) {
          display: block !important;
          height: 0 !important;
          margin: 0 !important;
          padding: 0 !important;
          border: 0 !important;
          overflow: hidden !important;
          line-height: 0 !important;
          font-size: 0 !important;
          break-before: avoid !important;
          -webkit-column-break-before: avoid !important;
        }
        #\(sectionID) {
          --kudos-ce-accent: \(accent);
          --kudos-ce-accent-label: \(label);
          --kudos-ce-accent-ink: \(lightInk);
          --kudos-ce-accent-sepia-ink: \(sepiaInk);
          --kudos-ce-accent-dark-ink: \(darkInk);
          --kudos-ce-surface: rgba(128, 128, 128, 0.08);
          --kudos-ce-surface: color-mix(in srgb, currentColor 6%, transparent);
          --kudos-ce-pill: rgba(128, 128, 128, 0.11);
          --kudos-ce-pill: color-mix(in srgb, currentColor 8%, transparent);
          display: block !important;
          box-sizing: border-box !important;
          width: 100% !important;
          max-width: 30rem !important;
          margin: 1.5rem auto 1rem auto !important;
          padding: 0.5rem 0 0 0 !important;
          font-family: \(uiFont) !important;
          font-style: normal !important;
          font-weight: 400 !important;
          letter-spacing: normal !important;
          word-spacing: normal !important;
          text-align: left !important;
          text-indent: 0 !important;
          hyphens: none !important;
          -webkit-hyphens: none !important;
          color: var(--USER__textColor, currentColor) !important;
        }
        :root[style*="readium-sepia-on"] #\(sectionID) {
          --kudos-ce-accent-ink: var(--kudos-ce-accent-sepia-ink);
        }
        :root[style*="readium-night-on"] #\(sectionID) {
          --kudos-ce-accent-ink: var(--kudos-ce-accent-dark-ink);
          --kudos-ce-surface: rgba(255, 255, 255, 0.08);
          --kudos-ce-surface: color-mix(in srgb, currentColor 9%, transparent);
          --kudos-ce-pill: rgba(255, 255, 255, 0.11);
          --kudos-ce-pill: color-mix(in srgb, currentColor 11%, transparent);
        }
        #\(sectionID) * {
          box-sizing: border-box !important;
          font-family: \(uiFont) !important;
          font-style: normal !important;
          letter-spacing: normal !important;
          word-spacing: normal !important;
          text-indent: 0 !important;
          hyphens: none !important;
          -webkit-hyphens: none !important;
        }
        #\(sectionID) svg {
          mix-blend-mode: normal !important;
          flex: 0 0 auto !important;
        }

        """
    }

    private static var ruleCSS: String {
        let sectionID = ReaderChapterEndHTML.sectionID
        return """
        #\(sectionID) .kudos-ce-rule {
          display: flex !important;
          align-items: center !important;
          gap: 0.75rem !important;
          padding: 0 0.875rem !important;
          margin: 0 0 0.875rem 0 !important;
          break-inside: avoid !important;
          -webkit-column-break-inside: avoid !important;
          break-after: avoid !important;
          -webkit-column-break-after: avoid !important;
        }
        #\(sectionID) .kudos-ce-line {
          flex: 1 1 0 !important;
          height: 0.5px !important;
          min-height: 0.5px !important;
          background-color: currentColor !important;
          opacity: 0.22 !important;
        }
        #\(sectionID) .kudos-ce-heading {
          font-size: 0.75rem !important;
          line-height: 1.33 !important;
          font-weight: 600 !important;
          letter-spacing: 0.05em !important;
          text-transform: uppercase !important;
          text-align: center !important;
          color: currentColor !important;
          opacity: 0.65 !important;
        }

        """
    }

    private static var noteCSS: String {
        let sectionID = ReaderChapterEndHTML.sectionID
        return """
        #\(sectionID) .kudos-ce-note {
          display: block !important;
          position: relative !important;
          border-radius: 1rem !important;
          padding: 0.875rem !important;
          margin: 0 0 0.875rem 0 !important;
          background-color: var(--kudos-ce-surface) !important;
        }
        #\(sectionID) .kudos-ce-note-heading {
          display: block !important;
          font-size: 0.8125rem !important;
          line-height: 1.385 !important;
          font-weight: 600 !important;
          color: currentColor !important;
          opacity: 0.65 !important;
          margin: 0 0 0.375rem 0 !important;
        }
        #\(sectionID) .kudos-ce-note-input {
          position: absolute !important;
          width: 1px !important;
          height: 1px !important;
          padding: 0 !important;
          margin: -1px !important;
          overflow: hidden !important;
          clip: rect(0, 0, 0, 0) !important;
          white-space: nowrap !important;
          border: 0 !important;
        }
        #\(sectionID) .kudos-ce-note-text {
          display: -webkit-box !important;
          -webkit-line-clamp: 4 !important;
          -webkit-box-orient: vertical !important;
          overflow: hidden !important;
          margin: 0 !important;
          font-size: 0.9375rem !important;
          line-height: 1.4 !important;
          text-align: left !important;
          color: currentColor !important;
          overflow-wrap: break-word !important;
        }
        #\(sectionID) .kudos-ce-note-input:checked ~ .kudos-ce-note-text {
          display: block !important;
          -webkit-line-clamp: unset !important;
          overflow: visible !important;
        }
        #\(sectionID) .kudos-ce-note-more {
          display: inline-flex !important;
          align-items: center !important;
          min-height: 2rem !important;
          margin: 0.25rem 0 0 0 !important;
          padding: 0.25rem 0 !important;
          font-size: 0.9375rem !important;
          line-height: 1.35 !important;
          font-weight: 600 !important;
          color: var(--kudos-ce-accent-ink) !important;
          cursor: pointer !important;
          -webkit-tap-highlight-color: transparent !important;
        }
        #\(sectionID) .kudos-ce-note-more span {
          color: var(--kudos-ce-accent-ink) !important;
        }
        #\(sectionID) .kudos-ce-note-input:focus-visible ~ .kudos-ce-note-more {
          outline: 2px solid var(--kudos-ce-accent-ink) !important;
          outline-offset: 2px !important;
          border-radius: 0.25rem !important;
        }
        #\(sectionID) .kudos-ce-less-text {
          display: none !important;
        }
        #\(sectionID) .kudos-ce-note-input:checked ~ .kudos-ce-note-more .kudos-ce-more-text {
          display: none !important;
        }
        #\(sectionID) .kudos-ce-note-input:checked ~ .kudos-ce-note-more .kudos-ce-less-text {
          display: inline !important;
        }

        """
    }

    private static var nextButtonCSS: String {
        let sectionID = ReaderChapterEndHTML.sectionID
        return """
        #\(sectionID) a.kudos-ce-next,
        #\(sectionID) a.kudos-ce-next:link,
        #\(sectionID) a.kudos-ce-next:visited,
        #\(sectionID) a.kudos-ce-next:hover,
        #\(sectionID) a.kudos-ce-next:active {
          display: flex !important;
          align-items: center !important;
          gap: 0.75rem !important;
          min-height: 3.5rem !important;
          padding: 0.75rem 1.25rem !important;
          margin: 0 0 0.875rem 0 !important;
          border-radius: 1.75rem !important;
          background-color: var(--kudos-ce-accent) !important;
          color: var(--kudos-ce-accent-label) !important;
          text-decoration: none !important;
          break-inside: avoid !important;
          -webkit-column-break-inside: avoid !important;
          transition: opacity 0.12s ease !important;
        }
        #\(sectionID) a.kudos-ce-next:active {
          opacity: 0.85 !important;
        }
        #\(sectionID) a.kudos-ce-next:focus-visible,
        #\(sectionID) a.kudos-ce-btn:focus-visible {
          outline: 2px solid var(--kudos-ce-accent-ink) !important;
          outline-offset: 2px !important;
        }
        #\(sectionID) a.kudos-ce-next *,
        #\(sectionID) a.kudos-ce-next:link *,
        #\(sectionID) a.kudos-ce-next:visited * {
          color: var(--kudos-ce-accent-label) !important;
          text-decoration: none !important;
        }
        #\(sectionID) .kudos-ce-next-text {
          flex: 1 1 0 !important;
          min-width: 0 !important;
          display: flex !important;
          flex-direction: column !important;
          gap: 0.125rem !important;
          text-align: left !important;
        }
        #\(sectionID) .kudos-ce-next-title {
          font-size: 1.0625rem !important;
          line-height: 1.29 !important;
          font-weight: 600 !important;
          overflow-wrap: break-word !important;
        }
        #\(sectionID) .kudos-ce-next-time {
          font-size: 0.8125rem !important;
          line-height: 1.23 !important;
          opacity: 0.86 !important;
        }

        """
    }

    private static var actionsAndFooterCSS: String {
        let sectionID = ReaderChapterEndHTML.sectionID
        return """
        /* Column pagination gives this row an indefinite inline size, so a grid
           track list collapses to one column. A 7rem floor stays two-up at the
           default size and wraps only when two buttons no longer fit. */
        #\(sectionID) .kudos-ce-actions {
          display: flex !important;
          flex-wrap: wrap !important;
          gap: 0.625rem !important;
          margin: 0 0 0.875rem 0 !important;
          break-inside: avoid !important;
          -webkit-column-break-inside: avoid !important;
        }
        #\(sectionID) a.kudos-ce-btn,
        #\(sectionID) a.kudos-ce-btn:link,
        #\(sectionID) a.kudos-ce-btn:visited,
        #\(sectionID) a.kudos-ce-btn:hover,
        #\(sectionID) a.kudos-ce-btn:active {
          display: flex !important;
          flex: 1 1 calc(50% - 0.625rem) !important;
          align-items: center !important;
          justify-content: center !important;
          gap: 0.4375rem !important;
          min-width: min(100%, 7rem) !important;
          min-height: 2.75rem !important;
          padding: 0.625rem 0.875rem !important;
          white-space: normal !important;
          border-radius: 1.375rem !important;
          background-color: var(--kudos-ce-pill) !important;
          color: var(--USER__textColor, currentColor) !important;
          font-size: 1rem !important;
          line-height: 1.25 !important;
          font-weight: 600 !important;
          text-align: center !important;
          text-decoration: none !important;
          transition: opacity 0.12s ease !important;
        }
        #\(sectionID) a.kudos-ce-btn:active {
          opacity: 0.78 !important;
        }
        #\(sectionID) a.kudos-ce-btn *,
        #\(sectionID) a.kudos-ce-btn:link *,
        #\(sectionID) a.kudos-ce-btn:visited * {
          color: var(--USER__textColor, currentColor) !important;
          text-decoration: none !important;
        }
        #\(sectionID) .kudos-ce-btn-label,
        #\(sectionID) .kudos-ce-kudos-label {
          min-width: 0 !important;
          white-space: normal !important;
          overflow-wrap: break-word !important;
        }
        #\(sectionID) .kudos-ce-kudos[data-kudos-given="true"] {
          opacity: 0.72 !important;
          cursor: default !important;
        }
        #\(sectionID) .kudos-ce-kudos[data-kudos-given="true"] .kudos-ce-heart-outline {
          display: none !important;
        }
        #\(sectionID) .kudos-ce-kudos[data-kudos-given="false"] .kudos-ce-heart-fill {
          display: none !important;
        }
        #\(sectionID) .kudos-ce-footer {
          margin: 0 !important;
          text-align: center !important;
          font-size: 0.8125rem !important;
          line-height: 1.385 !important;
          color: currentColor !important;
          opacity: 0.65 !important;
          break-inside: avoid !important;
          -webkit-column-break-inside: avoid !important;
        }
        @media (prefers-reduced-motion: reduce) {
          #\(sectionID),
          #\(sectionID) * {
            transition: none !important;
            animation: none !important;
          }
        }
        """
    }
}
