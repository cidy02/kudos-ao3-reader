# D8 result — round 2's accepted platform differences recorded

Sonnet 5.5 (agy account 2), branch `android/agent-sonnet-d8`. Changed: `docs/android-port/DECISIONS.md`
(one entry appended at the end, after D7's) and this file. Nothing built, committed, pushed or contacted.
The tiles are in `~/kudos-tools/pairs/tiles-r2/` (`pagejump.png`, `chapterpicker.png`, `recovery.png`,
`chsettingsedit.png`, `thread.png` among them). I did not re-judge them: the five items are Claude-CLI's,
as the brief gave them.

## Entry added

- **2026-10-23 · Round 2's accepted platform differences (Claude-CLI's judgement, recorded by Sonnet D8).**
  Round 2's re-shot pairs left the five differences below. Each loses nothing and is Android's own idiom or
  the demo data differing, so none is reported again. Paths are under
  `android/app/src/main/java/io/github/cidy02/kudos/`.
  - `pagejump`: First page and Last are plain text buttons on Android, filled pills on the iPhone; both use
    primary ink since A98. `ui/components/KudosPaginationBar.kt:286-296`.
  - `chapterpicker`: Android's chapter glyph is Material's open-book outline (`ImportContacts`) and its row
    titles are semibold accent; the iPhone uses SF Symbols' `book` and regular accent titles. Glyph
    `comments/CommentsScreen.kt:762` (used at `:526` and `:903`), row title `:909-912`. The comments
    screen's demo work is "A Test Work" on Android and "Sodium Lights" on the iPhone (demo data):
    `app/src/debug/assets/fixtures/ao3_comments_page.html:9`, shown at `comments/CommentsScreen.kt:419`.
  - `recovery`: the saved time is the platform's short date style, "10/22/26 10:57 PM" on Android and
    "10/22/2026, 8:50 PM" on the iPhone. `writing/WritingTextEditorScreen.kt:328` (drawn at `:280`, `:286`).
  - `chsettingsedit`: both apps hue the page from the challenge's title, else its slug (A98). The iPhone's
    demo challenge has no title, so it shows the slug and teal; Android's has one, so it shows the title and
    its own hue (demo data). `account/AO3ChallengeSignUpsScreen.kt:45-51` (hue),
    `account/AO3ChallengeSettingsEditScreen.kt:145` (subtitle), route `app/DebugShots.kt:68`.
  - `thread`: Android's page label is the demo work's title ("A TEST WORK"), the iPhone's "SODIUM LIGHTS"
    (demo data); the thread itself matches. `comments/CommentThreadScreen.kt:94` (kicker = work title),
    upper-cased at `ui/subject/SubjectComponents.kt:289`.
  Reversal: port the iPhone's form for any one of the first three if the owner prefers it; the last two are
  demo data, with nothing to reverse. The paired tiles are in `~/kudos-tools/pairs/tiles-r2/`.
  Evidence: `briefs/D8-result.md`.

## How each `path:line` was found

Shot name → route and effect key from `app/DebugShots.kt` (`:48` pagejump, `:54` chapterpicker, `:56`
thread, `:68` chsettingsedit, `:79` recovery), then a search of the named screen. Lines read in place.

| Item | Cited | How found |
|---|---|---|
| pagejump | `ui/components/KudosPaginationBar.kt:286-296` | `DebugShots.kt:48` → effect `"pagination"` at `KudosPaginationBar.kt:87` opens the page-jump sheet; grep `"First page"` gives `TextButton(onClick = { pageInput = "1" }` at `:286`, `Text("Last (…)")` at `:295`; both pass `textButtonColors(contentColor = tokens.primaryInk)` |
| chapterpicker glyph | `comments/CommentsScreen.kt:762`, `:526`, `:903` | `DebugShots.kt:54` → `Routes.comments`; grep `ImportContacts` → `internal val chapterPickerBookIcon = Icons.Outlined.ImportContacts` (`:762`); grep `chapterPickerBookIcon` gives its uses (scope chip `:526`, sheet row `:903`) |
| chapterpicker titles | `comments/CommentsScreen.kt:909-912` | the sheet row's `Text(chapter.displayName, fontWeight = if (isSelected) SemiBold else Normal, color = palette.accent)`. The "semibold" is the selected row's; the others are normal weight |
| demo work | `ao3_comments_page.html:9`, `CommentsScreen.kt:419` | grep `A Test Work` over `android/` (the only non-test hit is `app/src/debug/assets/fixtures/ao3_comments_page.html`, `<h2 class="title heading">`); header `title = workTitle` at `CommentsScreen.kt:417-419`, `workTitle` from `:203` |
| recovery | `writing/WritingTextEditorScreen.kt:328`, `:280`, `:286` | `DebugShots.kt:79` → `"text-editor"`; grep `DateFormat`: `recoveryDate` = `DateFormat.getDateTimeInstance(SHORT, SHORT)`; called at `:280` (copy chip) and `:286` (dialog text) |
| chsettingsedit hue | `account/AO3ChallengeSignUpsScreen.kt:45-51`, `AO3ChallengeSettingsEditScreen.kt:40`, `:145` | `DebugShots.kt:68` → `AO3ChallengeSettingsEditScreen(slug, title)`; `:40` wraps in `ProvideCollectionPalette(slug, title)`, which hues `title.ifEmpty { slug }` (`SignUpsScreen.kt:48`); `:145` shows `title.ifEmpty { slug }` as the subtitle |
| thread | `comments/CommentThreadScreen.kt:94`, `ui/subject/SubjectComponents.kt:289` | `DebugShots.kt:56` → effect `"comments-thread"` (`CommentsScreen.kt:195`); `SubjectHeaderBlock(kicker = workTitle, title = "Thread", …)` at `CommentThreadScreen.kt:93-95`; `SubjectKicker` upper-cases its text at `SubjectComponents.kt:289` |

The iPhone-side facts (filled pills, `book`, "Sodium Lights", teal, date text) are taken from the brief;
I did not read the Swift code.
