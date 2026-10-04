# Brief 3o result: Reading Insights

## iOS content, in display order

1. Pushed-screen chrome and header
   - Floating back chrome supplied by the pushed shell.
   - Toolbar `…` control containing the `Period` picker: `This month` and `This year`.
   - Pull to refresh.
   - Kicker: `Library`.
   - Title: `Reading Insights`.
   - With reading sessions, subtitle: `<hours> hours in <month/year> · stays on this device`.
   - Without sessions, subtitle: `Your reading activity stays on this device`.
2. Session activity, shown only when the selected period has recorded time
   - Section: `This month` or `This year`, with the number of weekly buckets.
   - Hours card:
     - total hours, to one decimal place;
     - `hours in <month/year>`;
     - when the previous period has rows, an up/down delta with signed hours and
       `vs <previous month/year>`;
     - weekly bars, oldest first, with an hours value and localized week-start label;
       the latest bucket uses the stronger accent.
   - Section: `Where the hours went`, with its row count.
   - Up to three named fandom rows, each with `<hours> h` and a proportional bar.
     Remaining fandom time and sessions that cannot be attributed to a visible work
     are folded into `Everything else`.
   - Section: `Pace and follow-through`.
   - Figures, in order: `<duration> median session`, `<rate> words per hour`,
     `<percent> of started works finished`, and `<N> day(s) longest streak`.
   - Footnote: `Reading time under 15 seconds isn't counted.`
3. No-session alternative
   - `No reading logged this month` or `No reading logged this year`.
   - `Kudos counts reading time only on this device, while a work is open in the reader. Your Library totals still appear below.`
4. Section: `Your library`, with the visible-work count
   - Figures, in order: `works opened`, `words read`, `still in progress`,
     `finished (<completion percent>)`, `opened in 7 days`, `opened in 30 days`,
     and `last read` (`Not yet` when absent).
   - Footnote: `Words read includes finished works when AO3 provides a word count. Recent activity counts each work you opened once. Finished includes works you completed before Kudos began recording time.`
5. Section: `Most-read fandoms`, shown only when nonempty
   - Up to six rows, each with the fandom name, number of started works, and a
     proportional bar.
6. Whole-screen empty state, used only when there is neither session time nor a work
   - Title: `No reading logged yet`.
   - Description: `Open a work and read for at least 15 seconds. Your reading activity stays on this device and isn't sent anywhere.`

### iOS number definitions mirrored on Android

- The selected period is the current calendar month or year. The delta uses the
  immediately preceding calendar period and is absent when that period has no rows.
- The activity chart uses the wider of the selected-period start and six weeks before
  now, matching iOS's separate headline and chart windows.
- Median ignores non-positive-duration rows and averages the middle pair for an even
  number of sessions.
- Words per hour is total stored words divided by total positive session time, not an
  average of per-session rates; zero-duration rows are ignored.
- Finish rate counts distinct work IDs, not sessions. No started works produces no
  percentage (`—`), rather than `0%`.
- A streak counts distinct local calendar days with a session; multiple sessions on
  one day count once.
- Session time is assigned to the visible work's first nonempty fandom. Only the top
  three are named; the rest and unattributed time become `Everything else`, so the
  rows still sum to total time.
- A Library work is started when it is finished or its canonical
  `SavedWork.hasStartedReading` is true. In-progress means started and not finished.
- Words read sums nonnegative AO3 word counts for finished works only.
- Seven- and 30-day activity use calendar-day windows: today plus the prior 6 or 29
  days, through now. Each work contributes at most once through `lastReadDate`.
- Most-read fandoms count each distinct fandom once per started work, then sort by
  count descending and name case-insensitively ascending.

## Differences found in the former Android implementation

### Missing content and controls

- It did not read `ReadingSessionEntity` rows, so it omitted total hours, prior-period
  delta, weekly activity, hours by fandom, median session, words per hour, period
  finish rate, longest streak, the 15-second note, and the no-session explanation.
- It had no month/year picker and no pull-to-refresh control.
- It had no pushed floating chrome, subject wash, `SubjectHeaderBlock`, status-bar +
  56dp top offset, subject panels, or theme-token bars.

### Different definitions or presentation

- The shelf calculations were already numerically aligned with iOS in the covered
  cases. The one implementation drift was that Android privately repeated every
  “started” field; it now defers to `SavedWork.hasStartedReading`, as iOS does, so a
  future model-field addition cannot silently undercount.
- `Works Read` displayed `startedWorks`, which means opened/started, not necessarily
  read to completion. It now reads `works opened`.
- `Last read` used an absolute medium date. iOS uses a named relative date, now also
  used on Android.
- Android's separate completion card added a progress bar and an `N of M` sentence;
  iOS presents the finished count and percentage as one Library figure.
- Android prefixed fandoms with rank numerals. iOS uses unnumbered colored bar rows.

### Different wording and order

- Former order: header → `Overview` → `Reading Activity` → `Completion` →
  `Top Fandoms` → one global privacy/definition footer.
- iOS order, now used: header → selected-period hours → `Where the hours went` →
  `Pace and follow-through` → `Your library` → `Most-read fandoms`.
- The former generic subtitle, section names, title-cased metric labels, activity
  phrasing, completion copy, fandom empty copy, and global footer did not match the
  iOS text. They were replaced by the exact labels and contextual notes listed above.

## User-visible string and callback audit

### Removed or replaced strings

| Former Android string | Disposition and reason |
|---|---|
| `Local-only progress from works in your Library.` | Replaced by iOS's dynamic hours/device subtitle. |
| `No statistics yet` | Replaced by `No reading logged yet`. |
| `Save works to your Library and open them in the reader to start tracking local reading insights.` | Replaced by iOS's 15-second, local-only empty-state description. |
| `Overview` | Removed; iOS has no overview section. Its figures are in `Your library`. |
| `Works Read` | Replaced by the accurate iOS label `works opened`. |
| `<N> in your library` | Removed; the `Your library` section header carries the count. |
| `Words Read` / `From finished works` | Replaced by `words read` plus iOS's full definition footnote. |
| `Finished` and its separate percentage detail | Combined as iOS's `finished (<percent>)`. |
| `In Progress` / `Started, not finished` | Replaced by `still in progress`. |
| `Reading Activity` | Removed; its figures now follow the iOS Library grid order. |
| `Past 7 days` / `Past 30 days` | Replaced by `opened in 7 days` / `opened in 30 days`. |
| `1 work opened` / `<N> works opened` | Removed; iOS displays the numeric figure beside the caption instead. |
| `Last read` with an absolute date | Replaced by lowercase `last read` with named relative time. |
| `Completion` / `Finished works` | Removed as a standalone section/card; represented in `Your library`. |
| `<finished> of <started> started works` | Removed; iOS shows count and percentage in one figure. |
| `Open a work in the reader to begin tracking progress.` | Replaced by iOS's no-session or whole-screen empty copy. |
| `Top Fandoms` | Replaced by `Most-read fandoms`. |
| Fandom rank numerals | Removed because iOS rows are unnumbered. |
| `No fandom insights yet` / `Fandoms appear after a started work has categorized AO3 tags.` | Removed because iOS omits an empty Most-read fandoms section. |
| `Statistics stay on this device. Words Read includes finished works with a known AO3 word count; recent activity counts distinct works opened.` | Split into iOS's header privacy statement and exact Library footnote. |

`Reading Insights`, `Loading Reading Insights`, `Reading Insights could not load`,
the fallback `Reading Insights could not be loaded.`, and `Not yet` remain.

### Callback and navigation diff

- The old screen exposed no user-action callback and contained no clickable action;
  therefore no existing callback was removed.
- `Routes.ReadingStatistics` still constructs `ReadingStatisticsScreen` with the same
  Library repository, settings repository, and shared privacy gate. The route now also
  supplies the existing `ReadingLogDao`; this is the only edit outside the four output
  files requested by the brief (`app/AppNavHost.kt`).
- Added internal callbacks: period selection recomputes the selected calendar window,
  and pull to refresh advances the reference time and recomputes the local flows.
- Back navigation remains owned by the pushed shell. The route and tab-bar behavior
  are unchanged.

## Could not do / remaining platform limitation

- Android has a real `reading_sessions` Room table and restores those rows from Kudos
  backups, so no session stat was invented or omitted. However, the Android reader
  currently has no call site that writes a new `ReadingSessionEntity`; only backup
  restore calls `upsertSession`. The session cards therefore report existing/restored
  rows accurately, but Android reading will not add new time until a separate reader
  logging task lands.
- No Room schema or backup-format file changed.
- Per the brief, Gradle was not run in this sandbox. Claude still needs to run the
  Android build/unit tests and perform the emulator visual check.
- No sign-in or AO3 request was made.
