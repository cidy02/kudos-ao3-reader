# Brief I10 (iOS): the second half's iPhone faults (A82b visual + A84b code)

Same worktree, branch and rules as I9/I9b (`/Users/cidy02/kudos-agent-ios`, `claude/agent-ios-i9`,
on top of your uncommitted I9/I9b work): compile iOS (arm64 simulator) and macOS with your own
derivedDataPath; no tests, no simulator, no commits, no sign-in, no AO3; lint at baseline. Write
`docs/android-port/briefs/I10-result.md` with `path:line` per item; propose tests where a rule
changes (Claude runs them).

Sources: `docs/android-port/briefs/A82b-result.md` (Gemini, tiles iPhone-above-Android at
`/Users/cidy02/kudos-tools/pairs/tiles-a82/<name>.png`) and your own `A84b-result.md`. Fix the iPhone
side of:
1. **Sepia misses** still open after I9b: `colsfilter` (the pinned Reset bar is white), `recovery`
   (the recovery sheet), `bulknames`, `pairing` (sheet and cards), `revokedevice` (the Reason card),
   `texteditor` (the bottom formatting toolbar's container). Check each against I9b first.
2. **AX5 truncation**: `seriesreorder` and `seriesremove` rows (SeriesEditView.swift:401, :540),
   `chapterform` ("After chapter" clipped in the Position row), `texteditor` (the footer "Recovery copy
   on this device · Save from the work form" and Done collapsing into a second ••• icon),
   `recovery` (heading, paragraphs and action labels), `parentpicker` (the "Language of the source"
   picker is cut at every size; the URL field at AX5), `availability` (the "Check Availability"
   heading), `revokedevice` (the sheet title is cut at every size), WritingTextEditorRow's second line
   (WritingTextEditor.swift:517), tag suggestion names (WritingTagsEditor.swift:286).
3. **Titles**: Co-creators and Inspired by name themselves twice (WorkAssociationPickers.swift:508,
   :596; set `.navigationTitle("")` as WritingTagsEditor does). `prefhelp`: a redundant "Privacy
   Preferences" card with a trailing ? badge sits under the sheet's own title and pushes the help
   below the fold — remove the duplication if the card adds nothing.
4. **aboutkudos**: the License card shows literal Markdown asterisks around "GNU Affero General Public
   License v3.0 (AGPL-3.0)"; render it as bold (Android does).
5. **seriesremove**: the iPhone opens "The Dawn Cycle · 0 works" with no works, while Android lists the
   three. The demo now serves `/series/<id>/manage` (`ao3_demo_series_manage`); find why the iPhone's
   remove view still has no works and fix it if it is the app, or say what demo data is missing.
6. The two select-mode counts you flagged (RecentlyDeletedView.swift:73, ReadingQueueOrganizer.swift:311):
   apply the fix you described if, on reading, the count really is never shown.

Leave for the owner, do not change: `colitems`' read-only Unrevealed/Anonymous vs Android's toggles —
just say in the result which one matches AO3's rules (who may change those fields).
Message me when done.
