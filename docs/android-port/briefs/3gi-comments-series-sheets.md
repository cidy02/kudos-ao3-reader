# Brief 3gi: Comments, your Series, What's New, My copy, the collection form (A71)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gi-result.md` FIRST; write each item into it as you
finish it: **fixed / not real / left**, `path:line`, the iOS code followed
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only), the test added.

Rules: iOS is the source of truth for layout, content and order; Android's navigation and chrome
are its own; "visual and UX parity with no lost features or information" (owner). Android's ICU
regex rejects some JVM-accepted flags (`RegexPortabilityTest`).

Pictures: `/Users/cidy02/kudos-tools/pairs/tiles2/<screen>.png` (top row iPhone, bottom row
Android; Dark, Light, Sepia, OLED, Sepia at the largest text). Claude confirmed 1 and 2 by eye and
in iOS's code; **check the others in iOS's code before changing anything**.

1. **Comments (tile `comments`).** (a) Under each comment iOS's Reply is accent text with its
   arrow, no capsule (`Features/Comments/CommentThreadRow.swift:1455`–`:1476`, "1f's Reply is plain
   accent text"); Android draws a filled "↩ Reply" pill. Keep the Inbox's pill, which iOS draws
   there. (b) A nested reply shows no chapter badge on iOS (`:827`, `parentAuthor == nil`); Android
   shows "Chapter 3". (c) **A comment's paragraphs run together on Android** ("That quiet thank you
   said everything. Absolutely broke me." is two paragraphs on iOS, from the fixture
   `ao3_comments_page.html`): find where Android reads a comment's body and keep paragraph breaks
   as iOS does. (d) The line naming the work's creators under the title is in the accent on iOS.
2. **Your Series (tile `myseries`).** Android prints "5 works, 54,679 words in the 2 loaded
   series" twice (under the title and again above the cards); keep it once (owner Q24: the totals
   stay). iOS has a "SERIES 2" section header; the series cards and Load More are iOS's
   `.cardRow()` (Android has `Modifier.cardRow()` in `ui/subject/SubjectComponents.kt`); Android's
   are glass panels, darker than the page in Light and Sepia. Android's "⋮" on your own series
   stays (Android's own actions).
3. **What's New (tile `whatsnew`).** iOS presents it as a full-height sheet with a centred title
   (`Features/Support/WhatsNew.swift`); Android's is a short bottom sheet with a left-aligned title.
4. **My copy (tile `mycopy`).** Android's rows are much taller, without dividers, so Activity,
   Origin and My tags fall off the screen; match iOS's row density and separators
   (`Features/WorkDetail/` My copy sheet). iOS shows "0%" progress for a work at 0; Android "—":
   check iOS's rule.
5. **The collection form (tile `colsettings`).** iOS draws the subject wash at the top of Edit
   collection (`Features/Account/AO3CollectionFormView.swift`); Android has none. The Tagline row's
   value is cut off on Android.
6. Tests: one per rule that can be pinned (paragraph breaks kept, nested replies without a chapter
   badge, the totals line once), each failing with its change undone.
