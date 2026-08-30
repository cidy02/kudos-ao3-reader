### 1. Correctness & Accessibility

* **Dynamic Type**: Fully correct. Each line uses standard semantic font scales (`.body`, `.footnote`, `.caption`) and `.fixedSize(horizontal: false, vertical: true)` inside a leading-aligned `VStack`, allowing proper multi-line wrapping and vertical expansion without clipping across all Dynamic Type and Accessibility sizes.
* **VoiceOver reading order**: Sequential and natural. VoiceOver reads elements top-to-bottom (`title` $\rightarrow$ `qualifier` $\rightarrow$ `aliases` $\rightarrow$ work count). Separating `title` and `qualifier` into discrete views provides an audible pause between the proper noun and its disambiguation tag.
* **Contrast & CJK Legibility**: **Problematic.**
  * System `.tertiary` (~30% alpha) yields only ~2.8:1 to 3.2:1 contrast against card surfaces across Light, Dark, Sepia, and OLED themes, failing the WCAG AA 4.5:1 minimum for regular text.
  * At `.caption` size (12pt), `.tertiary` contrast severely degrades the legibility of dense CJK ideographs (e.g., `僕のヒーローアカデミア`, `艦隊これくしょん`), where fine multi-stroke kanji blur together against the background.

---

### 2. Identity, Search, Zoom Key, and Works Query

* **Untouched.** The change in [`FandomListRow`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift#L368-L430) is strictly presentational. It does not modify tag identity, search indexing/filtering predicates, section index zoom keys, or navigation/work query bindings.

---

### 3. Hierarchy View

* **The three-tier structural hierarchy is correct.** Disambiguation (`qualifier`: medium/edition) and tag synonyms (`aliases`: localized titles/acronyms) serve distinct semantic purposes. However, the differentiation should rely on font size (`.body` $\rightarrow$ `.footnote` $\rightarrow$ `.caption`), not low-contrast `.tertiary` styling.

---

LAYOUT: FIX-THEN-SHIP
Required fix: In [`FandomListRow`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift#L402), change the aliases `foregroundStyle` from `.tertiary` to `.secondary` to maintain WCAG AA contrast and CJK stroke legibility while preserving the `.caption` font tier.
