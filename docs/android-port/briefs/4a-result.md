# Brief 4a result: large text in the shell and shared components

## Shared threshold

- iOS treats `dynamicTypeSize.isAccessibilitySize` as the structural breakpoint
  (`SubjectSurface.swift:496`, `SubjectScreen.swift:337`, `SubjectForm.swift:233`).
- Android now defines that breakpoint once as
  `isAccessibilityFontScale()` in `ui/subject/SubjectComponents.kt`: it returns
  true only when `LocalDensity.current.fontScale > 1.3f`.

## Component parity

### Tab bar

- **iOS rule:** `App/ContentView.swift:401-414` uses the system `TabView`/`Tab`,
  whose tab labels do not grow with Dynamic Type.
- **Android:** `app/MainScaffold.kt:545-554` already had the required port in
  commit `cd97c996`: the 11dp label, 24dp line height, and 0.5dp tracking are
  converted to sp through `LocalDensity`, cancelling `fontScale`. No further
  tab-bar change was needed.

### Subject kicker and chips

- **iOS rule:** `SubjectSurface.swift:440-454` scales the kicker type with an
  `@ScaledMetric`; `SubjectSurface.swift:1043-1061` does the same for chip text
  and both chip glyphs. Both stay one line.
- **Android:** `SubjectKicker` and `SubjectChip` already express text in sp and
  glyph dimensions through sp-to-dp conversion, so they scale with Android's
  font setting while retaining their existing one-line shape. Their scale-1.0
  layout is unchanged.

### Subject header block

- **iOS rule:** `SubjectSurface.swift:494-517` scales title/subtitle type; a
  multiword title is capped at two lines ordinarily and unlimited at an
  accessibility size, while a one-word title stays on one line. The minimum
  scale is 0.7 for multiword titles and 0.5 for one-word titles.
- **Android:** `SubjectHeaderBlock` uses the shared accessibility breakpoint for
  unlimited multiword titles and Compose text autosizing with the same 0.7/0.5
  floors. Ordinary two-line and one-word behavior remains unchanged.

### Section rule header

- **iOS rule:** `SubjectSurface.swift:595-605` scales the 11pt label and removes
  its one-line limit at accessibility sizes.
- **Android:** `SectionRuleHeader` now permits the uppercase section title to
  wrap only above font scale 1.3. Counts, notes, disclosure controls, spacing,
  and all ordinary-size behavior remain as before.

### Subject stat strip and progress ring

- **iOS rule:** `SubjectSurface.swift:804-816` scales the strip's 13pt values and
  9pt labels, capped through accessibility2; `SubjectSurface.swift:842-863`
  keeps each on one line with a 0.7 minimum scale. The progress-ring labels use
  a 0.6 minimum scale at `SubjectSurface.swift:928-940`.
- **Android:** sp already supplies the strip's font scaling, and Android's 2.0
  maximum needs no separate accessibility2 cap. Values and labels now autosize
  to the same 0.7 floor. `WorkProgressRing` derives label sizes and tracking from
  the ring's scaled dp diameter without applying `fontScale` twice, and both
  ring labels autosize to the 0.6 floor.

### Subject filter rail

- **iOS rule:** `SubjectScreen.swift:255-260` caps the rail at accessibility2.
- **Android:** no extra code is necessary because Android's maximum 2.0 font
  scale maps to that cap; its sp chip content continues to scale normally.

### Work ledger row

- **iOS rule:** `SubjectScreen.swift:335-371` scales title/metadata and changes
  the row from a horizontal layout to one vertical column at accessibility
  sizes. `SubjectScreen.swift:431-454` removes title and metadata truncation at
  that breakpoint.
- **Android:** `WorkLedgerRow` keeps its existing horizontal layout through 1.3,
  then stacks kicker, scaled progress ring, unlimited title, unlimited metadata,
  and scaled signal tray vertically. The existing ordinary two-line Android
  title cap is intentionally preserved so scale-1.0 screenshots do not change.

### Subject form row and values

- **iOS rule:** `SubjectForm.swift:229-233` scales the label and disclosure
  chevron; `SubjectForm.swift:270-278` stacks a value under its label at
  accessibility sizes while control rows remain horizontal. Value type scales
  and remains one line at `SubjectForm.swift:339-351`.
- **Android:** `SubjectFormRow` now stacks its standard `value` below the label
  only above 1.3. Custom trailing controls remain side by side. Label/value sp
  sizing and the disclosure glyph scale, while the 1.0 dimensions remain the
  previous 14.5sp and 18dp.

### Cover cards, status tray, and reading ring

- **iOS rule:** `CarouselCardStyle.swift:55-98` scales the 164 × 164√2 card in
  both dimensions, then applies one common clamp ratio so it stays within the
  window minus 16pt per side. The card's ring is an `@ScaledMetric` at
  `Features/Home/HomeCards.swift:11-13`. Status tiles scale together and are
  capped at accessibility2 (`WorkStatLabel.swift:327-339, 376-400`).
- **Android:** `SubjectWorkCoverCard`, the remote cover, and their skeleton now
  multiply width and height by `fontScale` and apply the same window-minus-32dp
  proportional clamp. Local cover rings multiply their diameter by `fontScale`.
  `HomeStatusTray` scales tile size, gaps, padding, glyphs, and corner geometry
  together. At 1.0 every dimension resolves to its previous value.
- `WorkReadingOrDownloadRing.kt` needs no separate branch: it forwards the
  scaled card diameter to the shared `WorkProgressRing` in both reading and
  downloading states.

### Work stat rows used by `SensitiveWorkRow`

- **iOS rule:** `WorkStatLabel.swift:29-52` keeps each icon/text stat together
  on one line; `WorkStatLabel.swift:765-789` lets complete stat units wrap in the
  flow layout. Status-grid geometry scales with the caption size at
  `WorkStatLabel.swift:339-400`.
- **Android:** `WorkStatLabel` and `WorkStatusChipRow` already flow complete stat
  units; their formerly fixed 14dp/13dp glyphs now convert from sp through
  `LocalDensity`, so glyphs grow with the surrounding labels. Cover status-grid
  geometry is scaled in `HomeStatusTray` as described above.

### Segmented controls

- **iOS rule:** the current iOS lane defines this shared control in
  `SubjectForm.swift:370-419` (rather than `SubjectSurface.swift`); its labels
  stay on one line and may shrink to 70% (`:399-403`).
- **Android:** both shared overloads are covered: `SubjectSegmentedControl.kt`
  and the older `items` overload in `SubjectComponents.kt` autosize 13sp labels
  down to 9.1sp. This includes the Author page's “Bookmarks” segment that was
  previously displayed as “Bookma…”.

## Could not port

None. The accessibility2 caps require no Android-specific clamp because the
largest Android step is the mapped maximum.

## Screen-specific large-text work still visible

These were observed but deliberately not changed in this shared-components
brief:

- `home/HomeResumeHero.kt:116-160`: the hero keeps a two-line title and a
  horizontal ring/location/Resume row with no accessibility reflow.
- `account/AccountInboxPane.kt:785-879`: Inbox identity, timestamp, subject, work
  title, chapter, and status lines retain fixed line limits inside horizontal
  rows.
- `account/AO3CollectionsScreen.kt:231-286`: AO3 collection cards keep the icon,
  kicker/status chips, two-line title, and chevron in one horizontal header.
- `library/LibrarySubjectComponents.kt:49-118`: local collection covers remain a
  fixed 164dp × 221dp family; this is outside the work-cover component changed
  here.

## Verification

- `git diff --check`: clean.
- Gradle/build/UI verification was not run, per the brief; Claude still needs to
  compile and compare screenshots at font scales 1.0 and 2.0.

## Review changes (Claude, before landing)

- **Auto-size minimums moved onto the 0.25sp step grid.** Compose's step-based auto-size counts up
  from the minimum, so with a minimum of 22.4sp a 32sp title could only reach 31.9sp: every
  multi-word title, stat cell and segment label shrank slightly at the normal font size. The
  minimums are now 22.5sp (titles), 9sp (stat values and segments) and 6.25sp (stat labels), each a
  whole number of steps below its maximum.
- **No auto-size on the progress ring's labels.** They are sized from the ring's diameter, which
  already grows with the font, so they keep their proportions at every size.

Checked on the emulator: 14 screens in OLED are pixel-identical to the build before this brief at
font scale 1.0 (`~/kudos-tools/pixdiff.sh`), and 12 screens were looked at at 2.0 and 1.5. Section
headers wrap instead of being cut, cover cards grow with their text, Settings rows stack their
value under the label, and long titles and segment labels shrink to fit. What still breaks at 2.0
is screen-specific and listed above, plus the Account hub's shortcut tiles (labels break
mid-word) and the Home hero (its status tray now overlaps the title).
