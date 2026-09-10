# Kudos redesign — plan, status, and handoff

**Branch:** `codex/kudos-redesign` · **Task row:** `T-212` in [`TASKS.md`](../TASKS.md)

Source of truth is the owner-supplied **Final Redesign Spec** design canvas —
87 artboards, 104 screens — now committed at
[`docs/design/Final_Redesign_Spec.dc.html`](design/Final_Redesign_Spec.dc.html)
so every agent on this branch reads the same version. This file is the
*durable* record of what it says and how far the implementation has got, so a
session that runs out of context can be replaced by a fresh one with zero
archaeology.

**Read the canvas with the tool, not with your eyes.** It is 2 MB of
inline-styled HTML; opening it burns context for nothing, and the numbers you
need are in the styles rather than in the rendering:

```
Scripts/redesign-spec-outline.py --list            # every artboard id + screens
Scripts/redesign-spec-outline.py --board 1k        # one artboard, as a tree
Scripts/redesign-spec-outline.py --notes           # every prose + "Needs building" note
```

Its two support files (`support.js`, `ios-frame.jsx`) were not part of the
upload, so the committed copy will not render as an interactive canvas — it is
committed to be *read*, which is what the outline tool does. Ask the owner for
a fresh export if you need the interactive version.

---

## 0. Environment constraint — read this first

**This branch is being worked on from a Linux container with no Swift
toolchain.** `xcodebuild`, `swift`, `swiftlint` and `swiftformat` are all
absent locally, so `Scripts/verify.sh` and every gate inside it **have not been
run** on these commits.

**The compile gate is CI instead.** `.github/workflows/unsigned-ipa.yml` builds
the iOS target on a `macos-26` runner and uploads an unsigned, sideloadable
`.ipa` per commit. Check it before trusting any commit here — a green run means
the branch *compiles*, and an artifact means it links and packages.

Verified so far:

| Commit | iOS build | Notes |
|---|---|---|
| `2d3696c` | ✅ green | First verified commit. Validates `SubjectSurface`, `SubjectScreen`, the Home hero, `SectionRuleHeader`. |
| `3f9a5ab` | ✅ green | Validates `WorkRow.ledger`, `scopeHue`, `Color.hueComponent`, `WorkLedgerRow`, `LibraryFilters.summaryLabels`, the chip rail. |
| `388d246` | ✅ green | Validates `SubjectChip.pill`, Library's Shelves/Ledger layout, `SensitiveWorkRow.providesNavigation`, and the artboard-1k results header with its figure strip and sort menu. |
| `d3d561b` | ✅ green | The fixed release step. |
| `7481229` | ✅ green | Validates the artboard-1k page sheet. **Published the first release.** |
| `d99594d` | ❌ red | Browse (1g). Half the change was lost to a `git checkout` recovery — see §3. |
| `cf58139` | ❌ red | Account (1m). Red for `d99594d`'s missing member, which it was stacked on, not for anything of its own. |
| `d4f64b8` | ✅ green | Restored `CategoryStats.clusterFandoms`. Validates Browse's panels **and** Account's header in one run. |
| `0abc06f` | ✅ green | The build stamp (`CURRENT_PROJECT_VERSION`, `KudosBuildCommit`) and About reading it. |
| `029eddb` | ✅ green | `SubjectStatStrip.Cell.tint`. |
| `d74cc7e` | ✅ green | Work Detail's artboard-1a identity block, and the `cardList()` wash fix under it. 10m29s. |
| `5ea4e0e` | ✅ green | The figure strip's strings as statements. 10m05s — within seconds of the run before it, which is the measurement that settles the false claim in its own commit message. See §3. |

Builds are published to **[Releases](https://github.com/cidy02/kudos-ao3-reader/releases)**
as a rolling per-branch pre-release tagged `build-<branch>`, and to each run's
artifacts for per-commit history. See the README.

What CI still does **not** cover:

- **SwiftLint / SwiftFormat** — `ci.yml` runs those separately; check it too.
- **The macOS target.** Only iOS is built here. Anything touching
  `#if os(iOS)` needs `Scripts/build-macos.sh` locally. Two such bugs were
  already caught by re-reading (see the `2d3696c` entry in §3).
- **The test suite.** `Scripts/test.sh` needs a booted simulator.
- **Anything visual.** The human screenshot gate in `AGENTS.md` is unsatisfied
  for every screen here. A green build says the layout compiles, not that it
  looks like the artboard — and several changes (the hidden navigation bar in
  particular, see §3) genuinely need a device.

Nothing here should be merged toward `merge-test` until the lint, macOS and
test gates have run and someone has looked at the screens.

---

## 1. What the redesign actually is

Every screen in the spec is built from the same parts, and all of them derive
from **one number: the subject's hue** — a fandom, a queue's stored colour, an
Account scope. That is the whole idea, and it is why the implementation starts
with a shared language file rather than with a screen.

| Part | Where it lives | Spec source |
|---|---|---|
| hue → wash / accent / chip / border | `SubjectPalette` | 1b, 1k, 1h |
| full-bleed page gradient | `.subjectWash(_:height:)` | 1k, 1l, 1t, 1u |
| kicker · rule | `SubjectKicker` | everywhere |
| kicker · rule · 32pt hero · tallies | `SubjectHeaderBlock` | 1k, 1l, 1t, 1u, 1h |
| section header with hairline + see-all | `SectionRuleHeader` | 1b, 1c |
| four-cell divided figure strip | `SubjectStatStrip` | 1k, 1h, 1i |
| 68pt read-progress ring | `WorkProgressRing` | 1b, 1o, 1t, 1ad |
| rounded-rect chip (neutral/tinted/dashed) | `SubjectChip` | 1k, 1an, 1h |
| 34pt circular glass chrome button | `GlassCircleButton` | 1k, 1l, 1h, 1r |

All of the above are in
[`kudos-ao3-reader/UIComponents/SubjectSurface.swift`](../kudos-ao3-reader/UIComponents/SubjectSurface.swift).

### Measured tokens (converted from the spec's CSS)

Do not re-derive these by eye from the canvas; they are already converted.

- Page background `#0b0b0d` → `ReaderTheme.cardBackdrop`.
- Page wash: `linear-gradient(178deg, …)`, stops at 0 / 26 / 52 / 74 / 100 %,
  saturation `.55 → .26`, brightness `.29 → .10`, resolving to the backdrop.
- Work card wash: `linear-gradient(158deg, …)` — **one hue**, brightness
  `.36 → .155`. (Codex's first pass shifted the hue by `+0.08` between the two
  stops; that is drift, and it made a single card read as two fandoms.)
- Ledger row wash: `linear-gradient(140deg, hue@40%, hue@30%)` over the page,
  hairline = accent at 22 %.
- Accent `#D9B26A` = hue, `sat .48`, `bri .86`. Accent-on-fill `#F4E4C6` =
  same hue, `sat .18`, `bri .97`.
- Kicker: `700 9–10px`, `letter-spacing .11em`, uppercase; rule `22×2.5`
  (26 wide on a page header), `border-radius 99`.
- Cover card: `164×232`, radius **16**, padding 12, shadow `0 4px 10px /.4`.
  Home hero: radius **18**, padding `16 18 18`, shadow `0 6px 14px /.45`.
- Progress ring: 68 pt, stroke 5, track `rgba(0,0,0,.3)`, fill `#fff`,
  round cap, `-90°`; `600 15px` tabular percentage over `600 8px` state word
  at `letter-spacing .09em`, `rgba(255,255,255,.6)`.
- Signal tray: radius 10, fill `rgba(255,255,255,.10)`, hairline
  `rgba(255,255,255,.16)`, padding `6×8` (24 pt tiles) / `5×6` (22 pt tiles),
  `space-between`. Tiles keep the existing `tileSize * 4/18` corner ratio —
  that already lands on the spec's 5.33 and 4.9 exactly.
- Chips: radius **8** (not capsules), padding `6×11`, `13px`; neutral =
  white 9 % on white 14 %; tinted = accent 24 % on accent 50 %; dashed =
  `0.5px` dashed white 26 %, no fill.
- Meta line: `11.5px`, `rgba(255,255,255,.62)`, values joined by a dimmed
  `·`, updated-date pushed to the trailing edge.
- Floating chrome: 34 pt circles, fill white 12 %, hairline white 16 %,
  `backdrop-filter: blur(14px)`.

---

## 2. Build order — by reachability

The owner's instruction is to build **in order of reachability**: the five tab
roots first, then what their rows push to, then sheets over those.

Tabs are `home, library, browse, account, search` (`AppTab` in
`App/AppRouter.swift`).

| Phase | Screens (artboard ids) | Status |
|---|---|---|
| **0** | Shared language + fixes to the foundation | ✅ done |
| **1** | Home tab — `1b`, then `1ad`, `1ae`, `1af`, `1ag` | 🟡 `1b`, `1ad`, `1ae`, `1af` done. `1ag` (Subscriptions) not started — it is the Account tab's list reached from Home, so it lands with Phase 6's `1p`. |
| **2** | Library tab — `1c` (shelves), `1d` (ledger) | 🟡 section headers, quick-filter pills, the Shelves/Ledger choice, and the pushed section pages are done. Left: Collections previewing four miniature works in ledger mode, and the Recently Deleted row. |
| **3** | Search — results `1k`, filter panel `1ao`–`1au`, tag picker `1av`–`1aw`, save `1ax` | 🟡 the row (Codex) and the results header, figure strip, sort control and chip rail are done. Left: the filter panel's own restyle (`1ao`–`1au`), the tag picker (`1av`/`1aw`), Save Search (`1ax`), and the paging switcher pill. |
| **4** | Browse — `1g`, `1al`, `1am`, `1an` | 🟡 `1g` done (category panels, fandom chip clusters, Jump Back In). Left: `1al`/`1am` (sibling-family grouping inside a category — needs the parser work the fandom audit deferred), and `1an` (the Browse filter sheet). |
| **5** | Account — hub `1m`, signed out `1n`, scopes `1bt` | 🟡 `1m`'s header and wash done (username as the page's own 32pt title, accent-hue wash, both layout branches); `1n`'s signed-out title with it. Left: the hub's own card treatment, and `1bt`'s scopes. |
| **6** | Account subsections in hub order — `1o`, `1q`, `1t`, `1p`, `1r`, `1s`, `1u`, `1v`, `1w`, `1x`, `1l`, `1y`, `1z`, `1ab`, `1ac`, `1aa` | ⬜ |
| **7** | Work detail `1a`; Comments `1f`, `1ba`, `1be`, `1bf` | 🟡 `1a`'s identity block done — page wash, fandom kicker / 32pt title / byline header, the rating·warnings·category·chapters figure strip, and the resume card with its 48pt ring. Left on `1a`: the summary in its serif face, the ON AO3 action chips, the tag clusters as `SubjectChip` groups, the series/collection/publication grouped card, the kudos·comments·bookmarks·hits strip, and the My copy row plus the sheet it opens (screen 2, which is today's Library tab). Comments not started. |
| **8** | Queues — `1h`, `1i`, `1j`, `1bg`, `1bh` | ⬜ |
| **9** | Local history & favourites — `1ah`, `1ai`, `1aj`, `1ak`, `1bc`, `1bd`, `1bi`, `1bj` | ⬜ |
| **10** | Collections — `1bk`, `1bl`, `1bm`, `1r`, `1s`, `1ci` | ⬜ |
| **11** | Writing surfaces — `1bn`–`1bs`, `1bu`, `1bv`, `1bw` | ⬜ |
| **12** | Challenges & moderation — `1bx`–`1by`, `1bz`–`1ch` | ⬜ |
| **—** | Empty/edge states threaded into their own phase — `1ay`, `1az`, `1bb` | ⬜ |

Phases 11 and 12 are mostly **AO3 write actions the app does not implement**
(see `docs/AO3_NETWORKING_POLICY.md`'s "must not implement" list, which is
binding). Treat those artboards as *layout* specs to be built when and if the
underlying capability lands — do not add network writes to satisfy a mockup.

---

## 2b. Review ledger

Multiple agents work this branch. This table is the record of **who wrote
what** and **whether anyone independent has looked at it**, so nobody
re-reviews settled work and nobody reviews their own.

### The rules

1. **An agent never reviews its own family.** Claude does not review Claude,
   Codex does not review Codex, Grok does not review Grok, Gemini does not
   review Gemini — regardless of version. A different version of the same model
   shares the same blind spots and the same house style, so it agrees with the
   original for the wrong reasons. Cross-family only.
2. **Add your row when you commit**, not later. One row per commit (or per
   tight run of commits that land one change), with your family name and the
   short SHA.
3. **Reviewed rows are closed.** If a row says `reviewed by <family>`, do not
   re-review it — read the finding notes and move on. Re-open a row only if you
   find a *new* defect in it, in which case add a fresh row for your fix.
4. **`unreviewed` is an invitation.** If you are from a different family than
   the author and you have capacity, that row is yours to review. Record the
   outcome in the Reviewed column: `<family> ✓` (no defects), or
   `<family> → <sha>` (defects found; fixed in that commit).
5. **State what you could not check.** A review from an environment with no
   compiler is a design/logic review, not a build. Say so in Notes — an
   unqualified ✓ implies the gates ran.

### Ledger

| Commit | Author | Change | Reviewed by | Notes |
|---|---|---|---|---|
| `38c42f4` | Codex | Redesign work-card foundation | Claude → `9ee86ba` | 5 spec drifts + 1 hit-target defect found; see §3. Not compiled. |
| `7fac768` | Codex | Refine redesign card hierarchy | Claude → `9ee86ba` | Reviewed together with `38c42f4`. Not compiled. |
| `9ee86ba` | Claude | `SubjectSurface.swift`; collapse onto one palette | unreviewed | Wants a non-Claude reviewer. Compiles (via `2d3696c`). |
| `436f7af` | Claude | Unsigned-IPA script + CI workflow; review ledger | unreviewed | Shell syntax checked (`sh -n`). |
| `620c82a` | Claude | Phase 1 Home: section headers, hero, counts; IPA workflow fixes | unreviewed | Compiles (via `2d3696c`). Not seen on a device. |
| `37bfac2` | Claude | Pin MuPDF clone; `SubjectScreen.swift` scaffold + ledger row | unreviewed | MuPDF pin verified by building it in CI. |
| `2d3696c` | Claude | Commit the canvas + outline tool; fix 3 compile errors in the new components | unreviewed | **iOS build green, IPA produced.** First verified commit on the branch. |
| `493fca9` | Claude | Stop the IPA workflow cancelling its own runs | unreviewed | Superseded by `98d6006`. |
| `835440d` | Claude | `WorkRow.ledger`; `scopeHue`; Home section pages | unreviewed | Compiles (via `3f9a5ab`). |
| `3f9a5ab` | Claude | `LibraryFilters.summaryLabels` + filter chip rail | unreviewed | **iOS build green.** Validates the whole ledger-row layer. |
| `aa56105` | Claude | Record CI as the compile gate in §0 | unreviewed | Doc only. |
| `3d81236` | Claude | `SubjectChip.pill`; Library quick filters at spec metrics | unreviewed | Compiles (via `388d246`). |
| `98d6006` | Claude | Per-SHA concurrency so every commit gets an IPA | unreviewed | CI config. |
| `3a5a0d6` | Claude | Library dashboard Shelves/Ledger (1c/1d); `providesNavigation` | unreviewed | Compiles (via `388d246`). |
| `bf17bcb` | Claude | README: where to find the IPAs | unreviewed | Doc only. |
| `19a0c61` | Claude | Publish the IPA to Releases, not just artifacts | unreviewed | Release step unverified at time of writing. |
| `388d246` | Claude | Search results header, artboard 1k | unreviewed | **iOS build green.** |
| `d3d561b` | Claude | Fix the release step (heredoc → `printf` + `--notes-file`) | unreviewed | Step executed locally against a stub `gh`. |
| `7481229` | Claude | Page sheet, artboard 1k, replacing the scrubber | unreviewed | **iOS build green**, and the release published from this run. |
| `7aaa16a` | Claude | `paths-ignore` so prose commits skip the build | unreviewed | Confirmed working: a doc-only commit triggered no run. |
| `98d6006` | Claude | Per-SHA concurrency so every commit gets an IPA | unreviewed | CI config. |
| `d99594d` | Claude | Browse, artboard 1g: category panels + fandom clusters; remove `MasonryLayout` | unreviewed | ❌ Build failed — half the change was lost to a `git checkout` recovery. Fixed in `d4f64b8`. |
| `cf58139` | Claude | Account, artboard 1m: username as the page title, accent wash | unreviewed | Build pending at time of writing. |
| `d4f64b8` | Claude | Restore `CategoryStats.clusterFandoms` | unreviewed | Fixes `d99594d`. **iOS build green** — carries `cf58139` too. |
| `4dd0ef3` | Claude | Rank what catches errors without a compiler | unreviewed | Doc only. |
| `0abc06f` | Claude | Build stamp in `CURRENT_PROJECT_VERSION` + About | unreviewed | **iOS build green.** |
| `029eddb` | Claude | Outline tool reads unlabelled artboards; `Cell.tint` | unreviewed | **iOS build green.** |
| `ed3eacb` | Claude | Stop `cardList()`'s backdrop hiding every wash | unreviewed | **Wants a non-Claude reviewer, and a screenshot.** Fixes a defect in five already-landed screens; see §3. Not compiled at time of writing, never seen. |
| `d74cc7e` | Claude | Work Detail, artboard 1a: the identity block | unreviewed | **iOS build green** (10m29s). Not seen. |
| `5ea4e0e` | Claude | Figure-strip strings as statements | unreviewed | **iOS build green** (10m05s). Behaviour-neutral. **Its commit message states a false reason** — see `40178c3` and §3. |
| `40178c3` | Claude | Correct that message; record the stale-poll trap | unreviewed | Doc only. |

**Family names to use:** `Claude`, `Codex`, `Grok`, `Gemini`, `Human`.
Version numbers are welcome in Notes but the family is what gates rule 1.

---

## 3. Status log

Newest first. Each entry: what landed, what it was verified against, what is
left. Keep appending — this is the handoff channel.

### 2026-09-10 — The wash was never drawing (Claude, `ed3eacb`)

**Read this before adopting the wash on another screen.** The gradient is the
most visible thing about the redesign and it had not painted a single pixel on
any `List` screen — Search, Account, and the Home and Library section pages all
shipped without it.

`cardList()` ends with `.background(theme.appTheme.cardBackdrop.ignoresSafeArea())`,
and every washed screen applies the two modifiers in this order:

```swift
List { … }
    .cardList()
    .subjectScreenWash(palette: …)
```

`.background` stacks *backwards*: the later modifier's layers go behind the
earlier one's. So the opaque `cardBackdrop` sat between the list and the
gradient and covered it completely.

What makes this worth a section rather than a line: **there was no symptom.**
No error, no warning, no layout difference — the screens looked exactly as they
had before the wash was added, and every one of them passed CI. The only thing
that could have caught it is a screenshot, which is the gate §0 says is
unsatisfied for every screen on this branch. Four separate commits added a
`.subjectScreenWash(…)` that did nothing, and each of them was written by
reading the previous one.

The fix is an environment flag (`EnvironmentValues.isOnSubjectWash`) that the
wash sets and `cardList()` reads, rather than a `paintsBackdrop:` parameter on
`cardList()`. A parameter has to be remembered at each call site and forgetting
it fails exactly this silently; the flag cannot be forgotten, because the wash
sets it itself. It only travels downwards, so the wash must stay *outside* the
`cardList()` it is meant to show through — which is where every call site
already puts it.

**The general lesson,** for the next agent working without a device: an edit
whose only evidence is visual has no gate at all here. CI proves it compiles,
and a compiling no-op looks identical to a compiling change. Prefer changes
whose correctness something can check — and where that is impossible, say so in
the commit rather than letting a green build imply more than it proved.

### 2026-09-10 — Phase 7 begins: Work Detail's identity block (Claude, `d74cc7e`)

**Landed.** `WorkDetailHeroCard` is gone, replaced by artboard 1a's three
opening statements, each sitting on the page wash rather than inside a card:

- `WorkDetailIdentityHeader` — the primary fandom as an accent kicker, the title
  at 32pt, and the author byline. The byline goes through `SubjectHeaderBlock`'s
  *trailing* slot rather than its `String` subtitle, because it has to stay a
  real `AO3AuthorBylineView`: every co-author is individually tappable through
  to their AO3 profile, and a string would have quietly dropped that.
- `WorkDetailFigureStrip` — rating · warnings · category · chapters, as the
  four-cell divided strip.
- `WorkDetailResumeCard` — a 48pt ring, where you stopped, and the one filled
  control on the page.

**Density: nothing on the screen was lost.** The 2×2 `WorkStatusIconGrid` in the
old card's corner stated the same four fields as colour-coded glyphs; the strip
states them spelled out, which is what a full-width page has the room for (the
grid stays on rows and cover cards, where it does not). The hero's
Language/Words/Chapters pills were already repeated verbatim by the Publication
and Work cards below it. The progress bar became the ring.

The one reduction is deliberate and worth knowing about: **the kicker names one
fandom** where the card listed all of them across up to three lines. The rest
become the kicker's dimmed `+5`, and the Tags section still lists every one. The
artboard heads the page with a single subject on purpose — it is the same
subject the whole page's hue is derived from.

**Three shared parts grew** to carry it, each usable by the screens still to
come: `SubjectHeaderBlock.kickerTrailingCount`, `SubjectStatStrip.Cell`'s own
VoiceOver text (the default reading of an abbreviated cell is "G RATING"), and
`WorkWarningStatus.figureText`/`.figureColor` — see §3b for why the last one
disagrees with `WorkWarningStatus.color`.

**The Read tile left the quick-action grid.** The resume card is that action
now; two controls for one action, a thumb-length apart, is a coin toss.

**Two facts 1a states that the app does not have:** the chapter's *title* and a
pages-left estimate. `SavedWork` stores a spine index and a last-read date, so
the card says "Chapter 3" and when — the same substitution `HomeResumeHero`
already makes, waiting on the same local reading log. A work nobody here has
opened gets **no ring**, rather than a 0% one that would claim a browsed remote
work is being tracked.

**Left on artboard 1a**, in the order the page runs: the summary in its serif
face; the ON AO3 action chips (Kudos / Subscribe / Bookmark / Mark for Later);
the tag clusters as `SubjectChip` groups under kicker labels; the grouped
series/collection/publication card; the kudos·comments·bookmarks·hits strip; the
two outline buttons; and the **My copy** row with the sheet it opens — which is
screen 2 of the artboard, and is today's Library tab rearranged. The four-way
segmented control survives underneath all of that for now; 1a is one continuous
page, so retiring the control is the last step of the screen, not the first.

### 2026-09-10 — Phase 1 continued: the ledger row and scope hues (Claude)

**The rule that was missing.** Spec 1m states it outright: *"the header wash is
the user's app accent colour — the crimson shown here is one instance of it,
not a fixed value"*. So the reds and crimsons in artboards 1ad / 1af / 1m are
**not literals to copy**; they are the default AO3 red seen through that rule.
That splits every surface in the redesign in two:

- Scoped to a **work, fandom or queue** -> that subject's own hue
  (`CoverArt.workHue(fandoms:title:)`, or a queue's stored colour).
- Scoped to a **tab or account section** -> `ThemeManager.scopeHue`, which is
  the app accent's hue, taken from `effectiveTint` so Sepia washes in its own
  warm brown rather than an accent it ignores everywhere else.

`Color.hueComponent` extracts it, alongside the existing `relativeLuminance`
and using the same `PlatformColor` pattern.

**Landed:**

- `WorkRow.Presentation.ledger` — the compact washed row from 1c/1d, 1ad, 1o,
  1t, 1u, 1x and 1ah: 44 pt ring, fandom kicker over its rule, title, one
  dot-separated metadata line, four-signal tray. Two presentations rather than
  a replacement, matching what `AO3WorkRow` already does for remote works, so
  unconverted screens keep exactly the row they had. Forwarded through
  `SensitiveWorkRow` so the privacy branches get it too.
- The 44 pt ring prints a bare figure ("42", not "42%") per 1d and 1ad —
  `WorkProgressRing.showsPercentSuffix`. VoiceOver still says "42 percent".
- `WorkLedgerRow.drawsBackground` — off inside a `List`, where
  `.cardRow(tintHue:)` paints the same wash at the row's true outer edge. Two
  backgrounds drew the hairline twice, half a point apart.
- `HomeSectionListView` (1ad / 1ae / 1af) now carries the wash, the
  kicker/rule/32 pt header as its first row, a `SectionRuleHeader` over the
  rows, and ledger rows.

**Staged deliberately.** Spec 1ad replaces the navigation bar with floating
glass circles. `subjectScreenChrome` does exactly that — but it takes every
`.toolbar` item with it, and this screen's filter button, overflow menu and
Select All all live there. So screens adopt `subjectScreenWash` first (wash,
header, ledger rows, transparent title-less bar) and the chrome swap lands
separately, **where someone with a simulator can check it**. Both modifiers
exist; only the staged one is wired.

**Still to do on these screens:** nothing — the filter chip rail landed in
`3f9a5ab` with `LibraryFilters.summaryLabels`.

### Browse: the spec asked for data that turned out to exist

Artboard 1g's build note says *"Featured fandoms per category are not in the
current parse — the category pages expose them, but `FandomListView` only reads
the full list."* True as far as it goes, and it points at the wrong fix.

The app already caches the **whole** per-category fandom list, each entry
carrying a work count (`FandomCatalog`, feeding `MediaBrowserView`'s stats
pass). So the cluster shows the category's **largest** fandoms — no new
request, no new parse, and arguably a better list than AO3's own featured set,
which is hand-curated and often stale. The sort happens in the existing
off-actor `computeStats`, never in the view: a category can hold nine thousand
fandoms.

The lesson generalises to the rest of the "Needs building" notes: **check what
the app already holds before believing a note that says data is missing.** The
spec's author was reasoning about AO3's endpoints, not about this app's cache.

### Known cosmetic debt from that change

`CategoryCardSkeleton` was shaped for a two-column masonry card — title lines
at 160/96pt, two stat blocks, narrow chips. It now sits in a full-width panel,
so it previews the right *structure* (it follows the panel stack) but at
column-width proportions. Not a bug, and deliberately not gold-plated: it is a
loading placeholder, and several screens are still unbuilt.

### Working from a container with no compiler: what actually catches errors

Ranked by what has caught real defects on this branch, not by what feels
thorough:

1. **CI.** It has caught things nothing else could, and it is the only gate that
   is not guesswork. Budget ~8 minutes a round trip and push early.
2. **Re-reading your own diff before committing.** Three certain compile errors
   in `2d3696c` were found this way. `git diff` the *whole* change, not the file
   you just touched — see below.
3. **Running the thing.** The release step passed `bash -n` and still failed on
   the runner; executing it against a stub `gh` would have caught it in seconds,
   and did once that was tried.
4. **Brace and `#if` balance checks.** Cheap, and they catch a truncated edit —
   but they are structural only. They cannot see a missing *member*.

**And one anti-pattern, which cost a commit message that says something false.**
Polling a run's job list can serve a cached response: the `steps` array keeps
saying `in_progress` long after the job has finished. Four polls in a row
returned byte-identical data — including an `updated_at` frozen at the second
the job *started* — and that was read as "the build is still going" rather than
as "this response has not changed". A build that had taken 10m29s and gone green
was written up in `5ea4e0e` as having ground for half an hour. The run after
it took 10m05s on the same runner, so the two agree to within seconds and
there was never an anomaly to explain.

So: **judge elapsed time from timestamps, not from repeated identical
responses.** A run's `created_at` and `updated_at` are in every reply; if
`updated_at` is not advancing, the response is stale, not the build. Reading the
*run* (`list_workflow_runs`) rather than its jobs gave the true state
immediately, and `date -u` against a run's `created_at` gives real elapsed
minutes in one line. Do that before concluding anything about how long a
build has taken — counting your own polls is not a clock.

**The trap that cost a build:** mid-refactor, an insertion landed at the wrong
anchor, and `git checkout -- <file>` was used to recover. That reverts the whole
file, silently discarding every *other* edit in it — in this case the
`CategoryStats.clusterFandoms` derivation the new view depended on. Braces still
balanced. The nine resulting errors all cascaded from one missing member.

So: **after a multi-step edit to one file, read `git diff` for that file end to
end before committing.** A revert-and-reapply is exactly when a half-applied
change looks finished.

### A CI trap worth not repeating

The release step failed in **zero seconds** with
`line 18: unexpected EOF while looking for matching quote`, pointing at a line
of English prose. The cause was not the quote: a **heredoc inside a YAML block
scalar** lost its terminator on the runner, so bash read the release notes as
code and stopped at the apostrophe in a possessive. The identical script passes
`bash -n` locally, which is what makes it worth writing down.

Two lessons, both now encoded in the workflow: **don't put a heredoc in a
`run:` block** (`printf` into a file and pass `--notes-file`), and **run the
step, don't just syntax-check it** — a stub `gh` on `$PATH` is enough to prove
the whole thing end to end.

### 2026-09-10 — Phase 0: shared language (Claude, `9ee86ba`)

**Landed:** `UIComponents/SubjectSurface.swift` — the nine shared parts listed
in §1, theme-aware across Dark / OLED / Light / Sepia.

**Review of Codex's two commits** (`38c42f4`, `7fac768`) against the current
spec. Codex built a real foundation — fandom-derived hue, the kicker, the
signal strip/tray, the ledger presentation on Search, and the cover-card
progress ring — and the *structure* is right. Findings, in severity order:

1. **Card wash shifted hue between stops** (`workCardGradient`,
   `workLedgerGradient`: `endHue = hue + 0.08`). The spec's card gradients are
   one hue at two brightnesses. Fixed in `SubjectPalette.cardWash`/`.rowWash`.
2. **Signal tray used `.ultraThinMaterial`.** The spec is a flat white-10 %
   fill with a white-16 % hairline; a blur over an already-translucent card
   wash reads as a smear. Fixed to the flat fill, theme-aware.
3. **`updateBadge` used the accent on `.ultraThinMaterial`.** Spec 1b draws
   `+2 NEW` as white on a white-16 % capsule, bottom-aligned in the card's
   flexible middle — not centre, and not accent-coloured.
4. **`.padding(-12)` after `.minimumHitTarget()`** on the ledger expand button.
   Negative padding leaves the 44 pt hit rect in place while shrinking the
   layout box, so the chevron's tap region overlaps the fandom kicker button
   sitting 5 pt to its left. Replaced with a real 20 pt visual slot inside a
   44 pt `contentShape`.
5. **Kicker `+N` took the accent colour.** Spec draws it at white 40 % — it is
   a count of what is hidden, not part of the subject's name.
6. `AO3WorkRow.ledgerMetadata` duplicates the count/zero-suppression logic in
   `WorkListStatsRow` (same `@AppStorage("showsZeroStats")`, same rules). The
   *output* is correct and matches the spec's meta line exactly — verified
   against 1k, which prints `English · 84,210 words · 11/11 · 212 comments ·
   3,204 kudos · 486 bookmarks · 61,904 hits` with the date pushed right — so
   this is a reuse debt, not a bug. Noted, not yet paid.

**Verified against:** artboards 1b, 1k, 1c, 1h (tokens read directly out of the
canvas's inline CSS, not eyeballed). **Not** verified by build or by eye — see
§0.

**Next step:** Phase 1, Home (`1b`).

### 2026-09-10 — Phase 1: Home, artboard 1b (Claude)

**Landed:**

- `WorkCarouselSection`'s hand-rolled header replaced by `SectionRuleHeader`.
  This is the highest-leverage single edit in the redesign: Home *and* Library
  both build their shelves from this one component, so both tabs take the
  spec's kicker / count / hairline / see-all treatment at once. Its `titleFont`
  parameter went with it — in the redesign every section header is the same
  11 pt kicker, so the "this is a subsection" override no longer means
  anything, and nothing passed it.
- `WorkCarouselSection` gained `itemCount`, wired on all four Home shelves.
  Suppressed while Subscriptions shows skeletons: a count printed beside a
  loading shelf would be the *previous* fetch's.
- `HomeResumeHero` rebuilt to 1b — fandom kicker, 31 pt title, the
  author · words · chapters dot line, the 68 pt ring against the chapter
  block, the Resume pill, and the signal tray floated in the corner over a
  94 pt reserved gutter so long titles wrap rather than run under it.
- Continue Reading's own header is now `SectionRuleHeader` too, with the
  collapse caret bound to the cover strip rather than the hero.

**Known gap, deliberate:** spec 1b puts the *chapter's title* under
"Chapter 12". `SavedWork` stores only `lastSpineIndex`, never a chapter title,
so the hero shows the last-read date instead — a real fact rather than an
invented one. Marked `TODO` in `HomeResumeHero.swift`; it wants the same local
reading log that artboards `1ah`/`1ai` depend on.

**CI finding:** the first `Unsigned IPA` run proved the SDK question is
settled — `macos-26` runners carry **Xcode 26.6 with iOS SDK 26.5**, which
matches the app target's `IPHONEOS_DEPLOYMENT_TARGET`. The run failed earlier,
in `Scripts/build-mupdf.sh`, and the workflow had two bugs of its own: it
cached `Vendor/MuPDF.xcframework` but the script writes to `build-mupdf/` and
installs nowhere, and the script redirects each slice's compiler output to its
own log file, so a failure surfaced as a bare `exit code 2`. Both fixed here;
the MuPDF `ios-sim` failure itself is still undiagnosed.

---

## 3b. Where the spec and the code disagree

Where an artboard contradicts a *reasoned* decision already in the codebase,
**the artboard wins** — it is the owner's design call, and that has been
confirmed explicitly. The reasoning it overrules should still be answered in
writing rather than silently dropped, so the next person to read that code
knows the argument was met and not missed.

### ✅ Resolved — "no warnings" is green here and gray everywhere else

**Decision: both, and they do not contradict.** Spec 1a paints the WARNINGS cell
green when a work has none. `WorkWarningStatus.color` paints that same state
gray, and its doc comment gives a good reason: AO3's own legend does, and in a
row of badge icons gray reads as "nothing flagged" against its red and orange
neighbours.

That reasoning is about a severity ramp of icons, and it holds there. It does not
transfer to a stat cell, where the state is the cell's *only* text: gray there
reads as dimmed-out, making the cell look less important than the three beside
it when what it says — this work carries no warnings — is a fact the reader came
looking for. So `figureColor` is green and `color` stays gray, with the split
named in both doc comments rather than one silently overriding the other.

`figureText` splits for a plainer reason: the cell's label already says
WARNINGS, so `text`'s "No Warnings" would state the field twice.

### ✅ Resolved — the paging control (spec 1k vs. `SearchPaginationBar`)

**Decision: the spec, implemented.** Recorded here because the reasoning it
overruled was good, and the next person to read `SearchPaginationBar` deserves
to know it was answered rather than ignored.

Spec 1k replaces the page **scrubber** with a page **sheet**: a number field,
the ten nearby pages as tiles, and First / Last for the ends.

The scrubber's own doc comment argued that a slider is how iOS moves through a
long ordered set, "because a thumb travelling 300pt can address 5,000 pages and
a row of pills cannot". True, and the spec answers it: the **field** addresses
all 5,000, and *exactly*, which a thumb never could — one thumb pixel is several
pages on a long list, so the slider was good at "somewhere around there" and bad
at "page 4,017". The tiles cover the other real case, stepping a few pages from
where you are, which is where a slider is fiddliest.

Both halves kept what mattered: nothing loads until you confirm, because paging
is a network fetch behind a politeness pacer and a tile that navigated on tap
would fire a request per tap.

The only part worth a test is the window's behaviour at the ends —
`nearbyPageWindow(around:totalPages:count:)` slides back inside the range rather
than truncating, so page 2 of 3,216 still offers ten choices. Four tests in
`KudosTests/SearchPaginationTests.swift`.

---

## 4. Working notes for whoever is next

- **Name things in full.** The owner's standing instruction for this branch:
  variable, property and function names should be verbose enough that a
  reviewer understands the code without tracing it. `signalTrayReservedWidth`,
  not `w`; `primaryFandomName`, not `fandom`; `resolvedReadingProgress`, not
  `p`. The same goes for the *why* — a comment that says what a number is for
  is worth more than the number's name. Several of these screens are read by
  another agent before a human ever sees them, and an abbreviation costs that
  reviewer a lookup every time.
- **Reuse before adding.** `docs/ARCHITECTURE_MAP.md` names the existing
  component for most of what the spec draws. The redesign is a restyle of
  those, not a parallel set. Before writing a new card/row/chip, check
  `UIComponents/` — `WorkStatusIconGrid`, `TagChip`, `StackedWorkCover`,
  `WorkBulkActionBar`, `FlowLayout` and `SkeletonLoading` all already exist and
  all appear in the spec.
- **Density is a gate, not a preference.** `AGENTS.md`: "a visually cleaner
  design that reduces scanability or hides metadata is considered a regression
  unless explicitly approved." The spec is *denser* than what ships today, so
  this mostly means: do not drop a stat because the mock had no room for it.
- **The spec is Dark-only.** Four themes ship. Every new colour goes through
  `SubjectPalette` or a `ReaderTheme` extension so Light and Sepia get a real
  answer rather than a dark one.
- **Artboards labelled "Needs building"** in the canvas depend on data the app
  does not have (a local reading log, per-queue completion state, featured
  fandoms per category, AO3 write endpoints). Those are separate engineering
  tasks; the redesign should not fake them. Where a screen cannot be honest,
  build the layout and leave the data path as an explicit `TODO` with the
  artboard id in it.
- The canvas can be re-read without the 2 MB file: `dv-opt` blocks carry the
  artboard id, `data-screen-label` names each screen, and `dv-build` notes say
  what AO3 does and does not allow. Extracting each screen to its own file and
  printing an indented outline of tags + inline styles is how the tokens in §1
  were measured.
