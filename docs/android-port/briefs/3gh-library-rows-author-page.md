# Brief 3gh: Library section rows and cards, another reader's AO3 page (A71)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gh-result.md` FIRST; write each item into it as you
finish it: **fixed / not real / left**, `path:line`, the iOS code followed
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only), the test added.

Rules: iOS is the source of truth for layout, content and order; Android's navigation and chrome
are its own (Material top bar, back arrow, icon buttons, tab bar); "visual and UX parity with no
lost features or information" (owner): where Android shows information iOS does not, keep it and
say so. Room migrations additive only (none expected). Android's ICU regex rejects some
JVM-accepted flags (`RegexPortabilityTest`).

Pictures: `/Users/cidy02/kudos-tools/pairs/tiles2/<screen>.png` (top row iPhone, bottom row
Android; columns Dark, Light, Sepia, OLED, Sepia at the largest text). Gemini's index:
`docs/android-port/audits/A71-result.md` in `/Users/cidy02/kudos-agent-gemini` (numbers are its).
Claude confirmed 1 by eye; **check every item in iOS's code before changing anything**.

1. **History and Favorites sections (A71 #4, #5; tiles `sec_history`, `sec_favorites`).** iOS draws
   these Library sections as compact rows: a progress ring, the fandom kicker, the title, one line
   "author · words · chapters" and the symbol tray; four or more fit a screen. Android draws the
   full ledger card (summary, figure lines, unfold chevron). Find iOS's rule
   (`Features/Library/LibrarySectionListView.swift`, `WorkRow.swift`; a per-section Layout default?)
   and match Android's row and default for each section it applies to (`library/` section list).
2. **Work cards in the other sections and lists (A71 #18; `sec_reading`, `sec_later`,
   `sec_finished`, `sec_downloaded`, `hsec_reading`, `hsec_updated`, `collection`).** iOS prints
   "by <author>" in the secondary colour, shows zero counts (comments 0, bookmarks 0), has no
   unfold chevron on these cards, and its card wash is lighter in Light and Sepia; Android colours
   the author, hides zeros, adds a chevron, and washes more strongly (and brown-tinted on
   `sec_later` in Dark/OLED). Compare iOS `WorkRow`'s card with `ui/components/SensitiveWorkRow.kt`
   and match what differs.
3. **Another reader's AO3 page (A71 #6; tile `author`, `-KudosDebugRoute author:Avery_Archive`).**
   Android washes it teal in every theme (Sepia too); iOS uses its own palette for the page (find
   it in `Features/Authors/AuthorProfileView.swift`). iOS chooses a pseud with a "Scope: All Pseuds"
   menu row; Android shows pills. Android adds a Works / In collections / Gifts row under the
   segmented tabs: check whether iOS shows that row on another reader's page (`WorksScopeAndSort`)
   and match. At the largest text Android clips the Subscribe label; fix if it is Android's.
4. Tests: one per rule that can be pinned (row choice per section, zero counts kept, the palette
   source), each failing with its change undone.
