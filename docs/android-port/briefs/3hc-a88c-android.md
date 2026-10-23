# Brief 3hc (Android): what the re-review of the re-shot screens found (A88c), part two

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex2`, branch `android/agent-gemini-3hc`,
from the lane's landing of 3ha). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Write
`docs/android-port/briefs/3hc-result.md` first; per item `path:line`, what changed, and per test what it does
with its change reverted. iOS is the reference (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`): read
the iOS view for every item before changing Android, and quote the iOS `path:line` you matched, copied
exactly from the file (Claude checks every quote; a quote that isn't in the file sends the item back). Reviews:
`/Users/cidy02/kudos-agent-ios/docs/android-port/briefs/A88c-cli-result.md` ("Left over from A88" and
"Small"). Tiles: `/Users/cidy02/kudos-tools/pairs/tiles-a88c/<name>.png` (left five columns iPhone: Dark,
Light, Sepia, OLED, largest text; then Android's five). Another agent (brief 3hb) is editing the writing
pickers, the reader sheets, the page-jump sheet and pager, queue tags, the text editor and the sheets'
cards at the same time: don't touch those. Match the surrounding code's style; the codebase is
hand-wrapped, don't reformat. No new dependencies.

1. **`collectionreorder`**: each row is its own card with gaps; the iPhone's rows are one card with
   dividers. Android's chapter picker already draws one grouped card with dividers (brief 3gz): reuse that.
2. **`newcollection` and `collectiondetails`**: Android has separate NAME and DESCRIPTION labels over
   outlined fields, and the swatch row on the page below; the iPhone has one COLLECTION card holding Name,
   Description and the swatches. Put them in one card the way iOS does (the outlined field style itself may
   stay).
3. **`newqueue`**: the Start From radio circles sit tight against their labels ("◉Empty") and there's no
   divider between the two rows; the iPhone spaces them and divides the rows.
4. **`addworks`**: Android's bylines drop "by", and one ("undertow") is in the accent while the first is
   grey; the iPhone's read "by uncle_iroh_fan", all in the same secondary colour.
5. **`chapterpicker`** (the comments chapter picker): Android's chapter icons are small page glyphs where the
   iPhone's are an open book, and the iPhone's row labels are all in the page's accent where Android's are
   plain (only the chosen row coloured).
6. **The "DRAFT" badge** (`seriesremove`, `seriesreorder`) reads "Draft" on the iPhone. If the badge is
   shared, check each place it appears against iOS before changing it.
7. **The works pages' card dates** (`fandomworks`, `tagworks`) read "09 Jul 2026" on Android and "07/09/2026"
   on the iPhone: iOS's `WorkStat.displayDate` (`UIComponents/WorkStatLabel.swift:1090-1117`; MM/dd/yyyy,
   en_US_POSIX, UTC). Android already has the same function, `WorkDetailDates.displayDate`
   (`works/detail/WorkDetailDates.kt:15`): use it for the remote work card's date wherever iOS's
   `AO3WorkRow` uses `displayDate` (`Features/Search/AO3WorkRow.swift:329`), and nowhere iOS doesn't.

Tests for every behaviour change, each failing with its change reverted (say how you'd revert it; Claude
runs them).
