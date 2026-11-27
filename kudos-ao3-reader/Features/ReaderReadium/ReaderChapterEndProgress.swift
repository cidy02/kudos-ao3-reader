#if os(iOS)
import Foundation
import ReadiumNavigator
import ReadiumShared
import WebKit

/// Keeps saved reading positions anchored to the original chapter prose when
/// the in-chapter end-of-chapter card adds height or an extra column at the end.
nonisolated enum ReaderChapterEndProgress {
    /// Normalizes a resource href, `readium.link.href`, `window.location.href`,
    /// or `window.location.pathname` so JS and Swift key the same chapter
    /// (preserving subdirectories and decoding `%xx`).
    ///
    /// A served page URL is `readium://<uuid>/OEBPS/ch.xhtml`. Stripping the
    /// scheme and host leaves the publication href the locator already uses.
    /// Keying only `location.pathname` misses when WebKit leaves that empty
    /// for the custom scheme, and the ratio is then never applied.
    static func normalizedHrefKey(_ href: String) -> String {
        var trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cut = trimmed.firstIndex(where: { $0 == "#" || $0 == "?" }) {
            trimmed = String(trimmed[..<cut])
        }
        if let scheme = trimmed.range(of: "://") {
            let afterScheme = trimmed[scheme.upperBound...]
            if let slash = afterScheme.firstIndex(of: "/") {
                trimmed = String(afterScheme[afterScheme.index(after: slash)...])
            } else {
                trimmed = ""
            }
        }
        while trimmed.hasPrefix("/") { trimmed.removeFirst() }
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        return decoded.lowercased()
    }

    private static func basenameKey(_ href: String) -> String {
        let normalized = normalizedHrefKey(href)
        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }

    /// Ratio for `href` from the map the page script fills.
    ///
    /// Full path first. A unique basename match covers a pathname that dropped
    /// its directories. Two stored chapters that share a filename do not match,
    /// so one chapter's card cannot scale the other.
    static func contentRatio(forHref href: String, in ratios: [String: Double]) -> Double? {
        let full = normalizedHrefKey(href)
        if let ratio = ratios[full] { return ratio }
        let base = basenameKey(href)
        guard !base.isEmpty else { return nil }
        let hits = ratios.filter { basenameKey($0.key) == base }
        guard hits.count == 1, let ratio = hits.values.first else { return nil }
        return ratio
    }

    /// Progression stored on a locator. Exactly `1` is the expanded document's
    /// end, past the card. Scroll mode seeks `0` and `1` in native code and
    /// never calls `readium.scrollToPosition`, so the in-page scale would not
    /// run and reopen would jump to the bottom of the card. A hair under 1
    /// still maps to the last position and restores at the end of the prose.
    static func progressionForRestore(_ normalized: Double) -> Double {
        normalized >= 1 ? (1 - 1e-6) : normalized
    }

    /// Maps a Readium-reported locator (whose progression divides by prose + card)
    /// back into original-prose coordinates (`0...1`), updating `position` and
    /// `totalProgression` with the same formula as `EPUBViewportAndLocationCalculator`.
    static func normalizeLocator(
        _ locator: Locator,
        contentRatio: Double,
        readingOrder: [ReadiumShared.Link],
        positionsByReadingOrder: [[Locator]]
    ) -> Locator {
        guard contentRatio.isFinite, contentRatio > 0.01, contentRatio < 0.9999,
              let rawProg = locator.locations.progression, rawProg.isFinite
        else { return locator }
        let normalizedProg = min(1.0, max(0.0, rawProg / contentRatio))
        guard abs(normalizedProg - rawProg) > 1e-6 else { return locator }

        let targetKey = normalizedHrefKey(locator.href.normalized.string)
        let targetBase = basenameKey(locator.href.string)
        let chapterIndex = readingOrder.firstIndex {
            normalizedHrefKey($0.url().normalized.string) == targetKey
        } ?? readingOrder.firstIndex {
            basenameKey($0.href) == targetBase
        }

        var updatedPosition = locator.locations.position
        var updatedTotal = locator.locations.totalProgression
        if let chapterIndex, positionsByReadingOrder.indices.contains(chapterIndex) {
            let chapterPositions = positionsByReadingOrder[chapterIndex]
            if !chapterPositions.isEmpty {
                let posIndex = min(
                    chapterPositions.count - 1,
                    max(0, Int(ceil(normalizedProg * Double(chapterPositions.count - 1))))
                )
                updatedPosition = chapterPositions[posIndex].locations.position
                if let start = chapterPositions.first?.locations.totalProgression {
                    let end = positionsByReadingOrder.indices.contains(chapterIndex + 1)
                        ? (positionsByReadingOrder[chapterIndex + 1].first?.locations.totalProgression ?? 1.0)
                        : 1.0
                    updatedTotal = start + normalizedProg * (end - start)
                }
            }
        }

        return locator.copy(locations: {
            $0.progression = progressionForRestore(normalizedProg)
            $0.position = updatedPosition
            $0.totalProgression = updatedTotal
        })
    }

    /// Document-end user script that measures original prose length vs total
    /// length (prose + `#kudos-chapter-end`), scales `readium.scrollToPosition`
    /// for saved progressions in `(0, 1)`, and posts `contentRatio` back to Swift.
    static func contentRatioUserScript(handlerName: String) -> String {
        """
        (function() {
            if (window.__kudosChapterEndProgressInstalled) return;
            window.__kudosChapterEndProgressInstalled = true;
            var anchorID = '\(ReaderChapterEndHTML.anchorID)';
            function originalContentRatio() {
                var anchor = document.getElementById(anchorID);
                if (!anchor) return 1;
                var se = document.scrollingElement || document.documentElement;
                if (!se) return 1;
                var vw = Math.max(1, window.innerWidth || 1);
                var vh = Math.max(1, window.innerHeight || 1);
                var scrollW = se.scrollWidth || vw;
                var scrollH = se.scrollHeight || vh;
                var view = document.documentElement.style.getPropertyValue('--USER__view').trim();
                var computed = window.getComputedStyle(document.documentElement);
                var writingMode = computed.getPropertyValue('writing-mode') || '';
                var isVertical = writingMode.indexOf('vertical') === 0;
                var isRTL = computed.getPropertyValue('direction') === 'rtl' || writingMode === 'vertical-rl';
                var rect = anchor.getBoundingClientRect();
                if (view === 'readium-scroll-on' && !isVertical) {
                    var anchorY = rect.top + (window.scrollY || se.scrollTop || 0);
                    if (!isFinite(anchorY) || scrollH <= vh) return 1;
                    var origH = Math.max(vh, Math.min(scrollH, anchorY));
                    return origH / scrollH;
                }
                var scrollX = Math.abs(window.scrollX || se.scrollLeft || 0);
                var proseEndX = null;
                var prev = anchor.previousElementSibling;
                while (prev) {
                    var pr = prev.getBoundingClientRect();
                    if (pr.width > 0 || pr.height > 0) {
                        proseEndX = isRTL ? ((vw - pr.left) + scrollX - 1) : (pr.right + scrollX - 1);
                        break;
                    }
                    prev = prev.previousElementSibling;
                }
                if (proseEndX === null || !isFinite(proseEndX)) {
                    proseEndX = isRTL ? ((vw - rect.right) + scrollX) : (rect.left + scrollX);
                }
                if (!isFinite(proseEndX) || scrollW <= vw) return 1;
                var lastProsePage = Math.max(0, Math.floor(proseEndX / vw));
                var origW = Math.max(vw, Math.min(scrollW, (lastProsePage + 1) * vw));
                return origW / scrollW;
            }
            if (window.readium && typeof window.readium.scrollToPosition === 'function') {
                var origScrollToPosition = window.readium.scrollToPosition;
                window.readium.scrollToPosition = function(position, dir, animated) {
                    var pos = parseFloat(position);
                    // Include 1. A saved end-of-prose progression of 1 must scale
                    // back onto the prose, not the bottom of the card. Scroll mode
                    // never reaches this for exactly 0 or 1; Swift stores a hair
                    // under 1 so the scale still runs.
                    if (isFinite(pos) && pos > 0 && pos <= 1) {
                        var ratio = originalContentRatio();
                        if (ratio > 0 && ratio < 1) {
                            return origScrollToPosition(String(pos * ratio), dir, animated);
                        }
                    }
                    return origScrollToPosition(position, dir, animated);
                };
            }
            function chapterHref() {
                try {
                    var link = window.readium && window.readium.link && window.readium.link.href;
                    if (link) return String(link);
                } catch (e0) {}
                var loc = window.location;
                if (!loc) return '';
                if (loc.pathname) return loc.pathname;
                return loc.href || '';
            }
            var lastPostedRatio = null;
            var lastPostedHref = null;
            function postRatio() {
                try {
                    var ratio = originalContentRatio();
                    var href = chapterHref();
                    if (!href) return;
                    if (lastPostedHref === href && lastPostedRatio !== null
                        && Math.abs(ratio - lastPostedRatio) < 0.0005) {
                        return;
                    }
                    lastPostedRatio = ratio;
                    lastPostedHref = href;
                    webkit.messageHandlers.\(handlerName).postMessage({
                        contentRatio: ratio,
                        href: href
                    });
                } catch (e) {}
            }
            window.addEventListener('load', function() {
                window.requestAnimationFrame(postRatio);
                if (typeof ResizeObserver === 'function' && document.body) {
                    var ro = new ResizeObserver(function() {
                        window.requestAnimationFrame(postRatio);
                    });
                    ro.observe(document.body);
                }
            });
            window.addEventListener('scroll', postRatio, { passive: true });
            // `readium.link` is assigned after the document-end scripts, in
            // spreadDidLoad. Retry until that href exists so the ratio is
            // stored under the same key as the locator, not only a pathname
            // that may not match it.
            var hrefTries = 0;
            function postUntilLinked() {
                postRatio();
                hrefTries += 1;
                var linked = window.readium && window.readium.link && window.readium.link.href;
                if (!linked && hrefTries < 8) window.setTimeout(postUntilLinked, 80);
            }
            postUntilLinked();
        })();
        """
    }
}

/// Non-observable per-open state held on `ReadiumBook` for the in-chapter
/// end-of-chapter card so `ReadiumBook.swift` stays lean.
struct ReaderChapterEndBookState {
    var kudosState: ReaderChapterEndKudosState?
    var styleState: ReaderChapterEndStyleState?
    var lastStyle: ReaderChapterEndStyle?
    var accentChangedSinceOpen = false
    var contentRatioByHref: [String: Double] = [:]
    var lastRawLocatorProgression: Double?
    /// Locator Readium reported, before card-length normalization. The ratio
    /// message often arrives after the first settle; re-applying it here keeps
    /// the saved place in prose coordinates.
    var lastRawLocator: Locator?

    mutating func reset(for chapterEnd: ReaderChapterEndWorkContext?) {
        kudosState = chapterEnd?.kudosState
        styleState = chapterEnd?.styleState
        lastStyle = chapterEnd?.style
        accentChangedSinceOpen = false
        contentRatioByHref = [:]
        lastRawLocatorProgression = nil
        lastRawLocator = nil
    }
}

extension ReadiumBook {
    /// Updates every loaded chapter-end card from "Give Kudos" to "Kudos Given"
    /// in place via Readium's navigator JS evaluation, and flips the shared state
    /// so chapters served later already carry "Kudos Given".
    func markChapterEndKudosGiven() {
        chapterEndState.kudosState?.isGiven = true
        evaluateChapterEndScriptOnLoadedSpreads(ReaderChapterEndHTML.markKudosGivenJS)
    }

    /// Updates the in-chapter card's accent custom properties on loaded spreads
    /// and future chapters if the user changes accent colour while reading.
    func updateChapterEndAccent(_ style: ReaderChapterEndStyle) {
        guard style != chapterEndState.lastStyle else { return }
        chapterEndState.lastStyle = style
        chapterEndState.styleState?.style = style
        chapterEndState.accentChangedSinceOpen = true
        evaluateChapterEndScriptOnLoadedSpreads(ReaderChapterEndHTML.updateAccentJS(style: style))
    }

    /// Re-syncs live kudos/accent DOM state after a chapter turn in case
    /// Readium's `WebViewServer` served a previously cached chapter resource.
    func syncChapterEndDOMStateIfNeeded() {
        if chapterEndState.kudosState?.isGiven == true {
            evaluateChapterEndScriptOnLoadedSpreads(ReaderChapterEndHTML.markKudosGivenJS)
        }
        if chapterEndState.accentChangedSinceOpen, let style = chapterEndState.lastStyle {
            evaluateChapterEndScriptOnLoadedSpreads(ReaderChapterEndHTML.updateAccentJS(style: style))
        }
    }

    @discardableResult
    func routeChapterEndActionURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == ReaderChapterEndAction.urlScheme else { return false }
        if let action = ReaderChapterEndAction(url: url) {
            onChapterEndAction?(action)
        }
        return true
    }

    func recordChapterContentRatio(_ ratio: Double, forHref href: String) {
        guard ratio.isFinite, ratio > 0.01, ratio <= 1.0 else { return }
        let key = ReaderChapterEndProgress.normalizedHrefKey(href)
        guard !key.isEmpty else { return }
        chapterEndState.contentRatioByHref[key] = ratio
        applyChapterEndRatioToLastRawLocator()
    }

    func normalizedLocatorForChapterEnd(_ locator: Locator) -> Locator {
        guard let ratio = ReaderChapterEndProgress.contentRatio(
            forHref: locator.href.normalized.string,
            in: chapterEndState.contentRatioByHref
        ) else { return locator }
        return ReaderChapterEndProgress.normalizeLocator(
            locator,
            contentRatio: ratio,
            readingOrder: readingOrder,
            positionsByReadingOrder: positionsByReadingOrder
        )
    }

    /// The first settle often lands before the page reports its ratio. Once the
    /// ratio arrives, rewrite that settle into prose coordinates so the
    /// debounced save is not the expanded-document progression (which reopen
    /// would scale a second time and walk backward).
    private func applyChapterEndRatioToLastRawLocator() {
        guard let raw = chapterEndState.lastRawLocator else { return }
        let fixed = normalizedLocatorForChapterEnd(raw)
        guard fixed != currentLocator else { return }
        currentLocator = fixed
        // Match locationDidChange: a scrub's transient settles are not a place
        // the reader stopped. currentLocator still updates so a dismiss mid-drag
        // flushes the corrected spot.
        if !isScrubbing {
            onLocatorChange?(fixed)
        }
    }

    private func evaluateChapterEndScriptOnLoadedSpreads(_ script: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.navigator?.evaluateJavaScript(script)
            if let root = self.navigator?.view {
                for webView in Self.allWKWebViews(in: root) {
                    _ = try? await webView.evaluateJavaScript(script)
                }
            }
        }
    }
}
#endif
