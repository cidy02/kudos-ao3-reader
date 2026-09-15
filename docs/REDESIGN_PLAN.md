# Kudos redesign — plan, status, and handoff

**Branch:** `codex/kudos-redesign` · **Task rows:** `T-212` (foundation, done), `T-213` (Codex screen polish), `T-214` (gating capabilities, Grok) in [`TASKS.md`](../TASKS.md)

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

> **Update 2026-09-11 — a Mac ran the gates for the first time** (Claude, Xcode
> 26.6, iOS 26.5 simulator, on `39e7eefa`; evidence in the Mac worktree's
> gitignored `build/mac-verify-2026-09-11/`). `verify.sh` stopped at 1/5; run
> gate by gate, 1–4 all failed and 5 checked nothing (clean tree). KudosTests
> did not compile. Once it did: 1,745 tests, 10 failures — five of them one
> SavedSearch crash. Fixed in `e7612188`…`a0143951` (see §3's top entry).
> **Still red:** SwiftLint's `ReadiumReaderView` type_body_length (inherited),
> and `build-macos.sh`'s product check, which needs a signing team the repo
> deliberately does not carry. The Linux-container text below is history.

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
| `5a6a12e` | ✅ green | Serif summary, ON AO3 chips, `SubjectFieldLabel`, the page row helpers. |
| `243580a` | ✅ green | **The whole form family** — `SubjectFormRow`, `subjectPanel()`, `SubjectRowSeparator`, `SubjectSegmentedControl` — plus 1a's facts card, tally strip, outline buttons and My copy row. |
| `d61ad69` | ✅ green | Tag clusters. |
| `74680bb` | ✅ green | Codex's T-213 WIP: locator chapter titles, the `@ScaledMetric` accessibility pass, `SensitiveWorkRow`'s navigation rework, the Saved-for-Later split. 11m24s. **Compiles — but the iOS suite, SwiftLint, the macOS build and screenshots that T-213 promised are all still unrun.** |
| `2e25947` | ✅ green | The access-level fix, and with it **all of artboard 1a** — one continuous page, My copy sheet, form family underneath. Published to Releases. |
| `cc5a890` | ❌ red | Four `'X' is inaccessible due to 'private' protection level`. `pageSections` assembles the page from blocks in four files and `private` is file-scoped. Fixed in `2e25947`. |
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

### 1a. The measured inventory — what the spec actually repeats

That table was written by reading screens. This one was counted:

```
Scripts/redesign-spec-inventory.py                # shared shapes, ranked
Scripts/redesign-spec-inventory.py --signature 23 # every artboard using shape #23
Scripts/redesign-spec-inventory.py --board 1m     # one screen's shapes, most-shared first
```

> 818 distinct shapes across 12,709 elements.
> 103 of them appear in 8+ artboards and account for **65% of every element drawn.**

Ranked by how many *artboards* use a shape, not how many times it is drawn — a
chip drawn forty times in one screen is that screen's list; a chip drawn once
each in forty screens is the design system.

| # | Boards | Uses | What it is | Built? |
|---|---|---|---|---|
| 3 | 75 | 174 | 34pt glass circle, blur 14 | ✅ `GlassCircleButton` |
| 4 | 69 | 605 | `.5px` hairline | ✅ used throughout |
| 5 | 68 | 116 | `700 10px`, `.11em`, uppercase | ✅ `SubjectKicker` (page) |
| 6 | 63 | 80 | `26×2.5` rule | ✅ `SubjectKicker` (page) |
| 7 | 62 | 77 | page wash, **380pt** | ✅ `subjectWash` default |
| 10 · 12 | 41 · 38 | 176 | tab item, selected pill / plain | ⚪️ **iOS 26's own tab bar** — not ours |
| 13 | 35 | 135 | radius 14 panel, `.5px` border | ✅ `SubjectStatStrip` ground |
| 14 | 33 | 146 | `22×2.5` rule | ✅ `SubjectKicker` (card) |
| 16 | 30 | **659** | `400 15px/1.3` body text | ✅ ambient |
| 17 | 30 | 126 | `600 11px`, `.07em`, uppercase form heading | ✅ `SubjectFieldLabel(.formGroup)` |
| 21 | 28 | 97 | `700 11px`, `.13em`, uppercase scope tab | ✅ **already** `SectionRuleHeader` |
| 22 · 35 | 27 · 21 | 60 | 44pt bar, 14pt gutter | ✅ `SubjectScreenScaffold` |
| 23 | 26 | **300** | row, `gap 10`, `padding 12×14` | ✅ `SubjectFormRow(.value)` |
| 24 · 39 · 61 | 26 · 20 · 14 | 71 | `700 32px`, `-.02em` | ✅ `SubjectHeaderBlock` |
| 25 | 24 | 127 | row, `gap 12`, `padding 11×14` | ✅ `SubjectFormRow(.control)` |
| 26 · 46 | 23 · 18 | 47 | **104pt** bottom gradient | ⚪️ **the tab bar's scrim** — not a header |
| 32 | 21 | 62 | `500 11px` monospace figure | ✅ `SubjectFormValue(isMonospaced:)` |
| 41 | 19 | 111 | `700 9px`, `.11em` | ✅ `SubjectKicker` (compact) |
| 45 · 52 | 18 · 14 | 295 | signal tray + its 22pt tiles | ✅ `WorkStatusIconGrid` |
| 55 | 14 | 56 | `700 7.5px` rounded rating letter | ✅ inside the tray |
| 58 | 14 | 17 | 36×5 sheet grabber | ⚪️ `.presentationDragIndicator` |

Three findings worth more than the table.

**The wash is 380pt in 62 artboards** — `subjectWash`'s default is the spec's own
number, and 1a's 620 is a real exception rather than a guess.

**The two most-used unbuilt shapes were rows, not decoration.** #23 alone is 300
elements across 26 artboards, all in the form and settings screens of Phases 5,
6, 11 and 12 — roughly fifty artboards built from about six shapes between them.
Nothing in the reachability order would have reached them for a long time. Both
now exist as `SubjectFormRow`.

**Checking before naming knocked three rows out of this table**, and it is worth
saying because the check takes a minute and each of these would have been a day.
#21 and #32 were already inside `SectionRuleHeader`. #26 is not a page header at
all — it is the scrim behind iOS 26's floating tab bar, the third thing this pass
found that looked like major shared work and belongs to the platform (the tab
item itself, #10/#12 in 41 artboards, and the sheet grabber, #58 in 14, are the
other two). **Roughly a third of what the ranking called "shared components"
turned out to be things this project must not build.**

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

## 2. Build order — parts first, then screens in reachability order

**Changed 2026-09-10, at the owner's direction.** The original order was purely
by reachability: tab roots, then what they push to, then sheets. That is still
how *screens* get assembled, and the phase table below is unchanged. What comes
before it is new.

Build **every shared part first, then assemble screens out of them.** The reason
is in §1a: 103 shapes account for 65% of the canvas, and going screen by screen
means meeting them one at a time, in the order the screens happen to need them.
Every screen built so far has turned up another part that should have existed
already — `SubjectFieldLabel`, `pageBodyRow`, `panelGutter`,
`kickerTrailingCount`, a warning figure colour — each obvious afterwards and
none visible in advance. Discovering a part mid-screen also means designing it
against one caller, which is how a shared component ends up with the first
screen's assumptions baked into it.

So the sequence is:

1. **Count, don't guess.** `Scripts/redesign-spec-inventory.py` ranks shapes by
   how many artboards use them. A shape in twenty artboards is a component; a
   shape in one is that screen's own business and should stay there.
2. **Check what already exists** before naming anything new.
   `docs/ARCHITECTURE_MAP.md` and `UIComponents/` hold most of it, and two
   entries in §1a's table turned out to be *the platform's* — the floating tab
   bar in 41 artboards is iOS 26's own, and the sheet grabber in 14 is
   `.presentationDragIndicator`. Neither is ours to build, and both looked like
   major shared components until someone checked.
3. **Build the part, with every caller in view.** `--signature N` lists every
   artboard that uses a shape; read three or four of them before fixing the API,
   so the shape of the type comes from the spread rather than from whichever
   screen is being built today.
4. **Then assemble screens**, in the reachability order below.

### The parts — all built as of `243580a`

Ranked as §1a ranks them. Kept as a record of what each one cost and unlocked,
because the next inventory pass over a later spec should expect the same shape
of answer: a few genuine components, several already built, and a third that
belong to the platform.

| Part | Boards | Uses | Notes |
|---|---|---|---|
| **Form row** | 26 | 300 | Built as `SubjectFormRow.value` — label flexes, value trails. |
| **Hub row** | 24 | 127 | Built as `SubjectFormRow.control` — label hugs, control flexes. One type with the two arrangements, since that is the only thing that differs and it is the rule for choosing. |
| **Form section header** | 30 | 126 | Built as `SubjectFieldLabel(style: .formGroup)` rather than a third uppercase label in the same file. |
| **Scope tab strip** | 28 | 97 | **Already existed** as `SectionRuleHeader` — same 11pt/`.13em`, same monospace count. |
| **Compact page header** | 23 | 47 | **Not a header.** The bottom scrim behind the floating tab bar. Nothing to build. |
| **Monospace figure** | 21 | 62 | Built as `SubjectFormValue(isMonospaced:)`, and already present inside `SectionRuleHeader`'s count. |

Also built alongside them, because the rows needed them: `subjectPanel()` (the
radius-14 glass ground, which turned out to be the one `SubjectStatStrip`
already drew), `SubjectRowSeparator`, and `SubjectSegmentedControl` — the
spec's own 9pt-over-7pt inline control, which is not a `Picker(.segmented)`
because that one clips rather than reflows at accessibility text sizes.

Tabs are `home, library, browse, account, search` (`AppTab` in
`App/AppRouter.swift`).

### Assembly order (unchanged)

| Phase | Screens (artboard ids) | Status |
|---|---|---|
| **0** | Shared language + fixes to the foundation | ✅ done |
| **1** | Home tab — `1b`, then `1ad`, `1ae`, `1af`, `1ag` | 🟡 `1b`, `1ad`, `1ae`, `1af` done. `1ag` (Subscriptions) not started — it is the Account tab's list reached from Home, so it lands with Phase 6's `1p`. |
| **2** | Library tab — `1c` (shelves), `1d` (ledger) | 🟡 section headers, quick-filter pills, the Shelves/Ledger choice, and the pushed section pages are done. Collections' four miniature works landed 2026-09-11 (`d0526c0e`); the Recently Deleted row was already built. |
| **3** | Search — results `1k`, filter panel `1ao`–`1au`, tag picker `1av`–`1aw`, save `1ax` | 🟡 results header done. Filter panel: `1ap` includeColor, `1ar` searchable language picker, `1at` five range sliders landed (`5100addb`). `1ao`/`1aq`/`1as`/`1au`/`1av`/`1aw` confirmed matching the code — no change. `1ax` naming alert + Search idle listing already exist (`SavedSearch`); left alone. The paging switcher pill landed 2026-09-11 (`3eeabd89`). |
| **4** | Browse — `1g`, `1al`, `1am`, `1an` | 🟡 `1g` done. `1al`/`1am` sibling-family grouping and `1an` filter sheet landed (`a0913bf6`). Category-card work total is now marked approximate (the naive sum of tag counts). The family page runs a real `filter_ids:(A OR B)` union as of 2026-09-12 (`aab42504`), falling back to the join — and its tilde — when an id will not resolve. |
| **5** | Account — hub `1m`, signed out `1n`, scopes `1bt` | 🟡 `1m`'s header and wash done (username as the page's own 32pt title, accent-hue wash, both layout branches); `1n`'s signed-out title with it. Left: the hub's own card treatment, and `1bt`'s scopes. |
| **6** | Account subsections in hub order — `1o`, `1q`, `1t`, `1p`, `1r`, `1s`, `1u`, `1v`, `1w`, `1x`, `1l`, `1y`, `1z`, `1ab`, `1ac`, `1aa` | 🟡 `1o`/`1q`/`1t`/`1p` share `AO3AccountWorksList`'s 1o header; **`1p` also has its "X New" badge and the `SubscriptionWatermarks` store behind it**. `1ac` Privacy done. Left: `1r`/`1s` (collections, Phase 10), `1u`/`1v`/`1w` built 2026-09-11 (`578a0bac`), `1x` Drafts now opens native drafts/forms through T-215, `1l` Inbox and `1z` Preferences **restyled 2026-09-11** (`a01c857c`, fixed in `40250315`), `1y` Dashboard (it is `AuthorProfileView`, shared with viewing other authors). `1aa` **built 2026-09-11** (`d8a7192b`) — its seven archive paths were verified live first; `1ab` is `ReaderOptionsForm`, shared with the reader. |
| **7** | Work detail `1a`; Comments `1f`, `1ba`, `1be`, `1bf` | ✅ **`1a` done, both screens** (identity block, serif summary, ON AO3 chips, tag clusters, grouped facts card, tally strip, outline buttons, My copy row; the segmented control is retired and the page is continuous). **Comments done 2026-09-13**: `1f` chrome (header, COMMENTS/THREADS/YOURS/LATEST signal strip, chapter + sort pills, section rule, write pill, wash), `1ba`/`1be` composer (quoted parent on the rail, identity + character budget, format bar pinned to the sheet edge, detents rather than two layouts), `1bf` formatting tray (`CommentMarkup.swift` — a tag-aware buffer writing only tags AO3's sanitizer keeps). **Two caveats:** only COMMENTS is a site total — the other three count the loaded page and say so under the strip; and 1f's *threading* model is parked as an open question in §3b, since it is the elbow style T-151 already dropped on device. Comment streaming not built: the model pages and has no append path. |
| **8** | Queues — `1h`, `1i`, `1j`, `1bg`, `1bh` | 🟡 `1h`/`1i`/`1j`/`1bg` built 2026-09-11. **`1bh` refused**: a shared-queue tag manager needs collaboration and queue tags, neither of which exists. |
| **9** | Local history & favourites — `1ah`, `1ai`, `1aj`, `1ak`, `1bc`, `1bd`, `1bi`, `1bj` | ✅ **all built except `1bc`'s "with new work" half**, which needs a fandom-page newest-works parse that does not exist. `1bi` Insights, `1bj` Recently Deleted, `1ah`/`1ai` history grouping, `1aj`/`1ak`/`1bd` favourites scopes. Rules in `ReadingInsights`, `LibraryHistoryGrouping`, `ReadingAffinities` — 30 tests, none compiled by CI. |
| **10** | Collections — `1bk`, `1bl`, `1bm`, `1r`, `1s`, `1ci` | 🟡 **`1r` list, `1bm` sort/filter, `1ci` detail and `1bl` create/edit all built** on `561f848b`'s networking. **`1bk` is NOT done** — corrected 2026-09-14, see §3b. A local collection is created through a bare name field; the artboard draws a form. **Left: `1s`** — the staged manage-items screen (`updateCollectionItems` exists; the staging UI does not). Close/delete stay Open on AO3. |
| **11** | Writing surfaces — `1bn`–`1bs`, `1bu`, `1bv`, `1bw` | 🟡 `1bn`/`1bo`/`1bp`/`1bq` built 2026-09-12 (`2d5245a3`); T-215 connects work/chapter forms, while bulk/tag-only routes remain unwired. **networking landed** (`bac33974`): `AO3Client+Works` / `AO3WorkActions` / `AO3TagAutocomplete` (reuses existing `autocompleteTags`). `1bv` editor + native draft entry and required/tag inputs are implemented in T-215; remaining association/series/preview controls still need wiring. Series create from `/series/new` is Open on AO3. |
| **12** | Challenges & moderation — `1bx`–`1by`, `1bz`–`1ch` | ✅ All 11 screens built 2026-09-12: `1bx`/`1by`/`1bz`/`1ca`/`1ce` (earlier batch) plus `1cb`/`1cc`/`1cd`/`1cf`/`1ch` (this batch). **All reachable** as of this batch too — a "Manage" section on `AO3CollectionDetailView` (1ci), gated on `isMaintainer`/`auth.isLoggedIn`/`dashboard.*URL`. Matching (`1cb`/`1cf`) and tag-set association/approval (`1ch`) stay Open on AO3 — confirmed no client write exists for either, not just assumed. **Left:** no "Tag Set" row is wired — nothing parses a `tagSetID` for a given collection yet, so `TagSetView` is complete but only reachable by hand-supplying an id. |
| **—** | Empty/edge states threaded into their own phase — `1ay`, `1az`, `1bb` | 🟡 `1ay` and `1az` landed in `5100addb`; `1bb` (Preferences saved) landed with 1z in `a01c857c`. |

### Correction (2026-09-10): what the write policy actually says

This section used to read: *"Phases 11 and 12 are mostly AO3 write actions the
app does not implement (see `docs/AO3_NETWORKING_POLICY.md`'s 'must not
implement' list, which is binding)."* **That was wrong on both halves**, and it
had been repeated into a hand-off prompt before anyone read the policy itself.

**Writes are not prohibited, and many are implemented.** `AO3WriteActions.swift`
carries `giveKudos`, `postComment`, `toggleSubscribe`, `markForLater` and
`saveBookmark`; `AO3CommentActions`, `AO3InboxActions`, `AO3PreferencesActions`
and the author profile's block/mute all POST too. Artboard `1ba`'s own note —
*"posting comments is an AO3 write the app does not implement"* — is **stale**:
`postComment` exists, with a whole `CommentSubmission` de-duplication layer
around it.

**The constraint that does govern this work: every AO3 request goes through the
established client.** There are exactly two `URLSession` instances in the whole
Services layer — anonymous in `AO3Client`, authenticated in `AO3AuthService` —
and the policy names the one sanctioned exception. A new endpoint is a new
method *on those types*, never a new client. `getHTML` / `imageData` for
anonymous reads, `authenticatedPageHTML` over an
`AO3AuthService.authenticatedRequest` for authenticated ones, `submitWrite` for
every write, `AO3RequestCoordinator.withSlot` around anything that fans out,
`RequestCoalescer` for repeated identical in-flight GETs.

Hand-rolling one does not merely break style: it silently drops the host
allow-list, the ≥0.6s pacer, the identifiable contact User-Agent, `Retry-After`
handling, the three-slot concurrency cap and the redirect cookie relay. Each is
a promise to AO3, and the policy opens by calling respectful access a hard
product requirement because community trust is the whole ballgame.

**The policy's "must not implement" list is otherwise about request discipline,
not about writes as a category.** What it forbids is: request fan-out outside
`AO3RequestCoordinator`, raw `URLSession` calls that bypass `AO3Client`, retry
loops or auto-retry UI around writes, background polling, bulk scraping of
logged-in pages, weakening pacing/cooldowns/`Retry-After`/the contact UA, and
touching local works in any network error path. A write itself is fine —
`submitWrite` is single-shot, never retried, never coalesced (the double-kudos
risk), CSRF from `authenticatedPageHTML`, and a 429 is surfaced rather than
auto-retried.

**So Phases 11 and 12 need endpoints built, not deferred.** The policy is a
*centralisation and politeness* rule, not a ceiling on what the app may do.
Where an artboard needs a call the app lacks, the answer is to add it where the
others live — following the file pattern already established here:

| Kind | File | Shape |
|---|---|---|
| Reads | `AO3Client+<Area>.swift` | extension on `AO3Client`; `getHTML` or the authenticated equivalent, then SwiftSoup parsers |
| Writes | `AO3<Area>Actions.swift` | extension on `AO3AuthService`; one CSRF page fetch, then a single `submitWrite` POST |

`AO3Client+Comments`, `AO3Client+Inbox`, `AO3Client+Preferences`,
`AO3CommentActions`, `AO3InboxActions`, `AO3PreferencesActions` and
`AO3WriteActions` are worked examples; collections and challenges would be
`AO3Client+Collections.swift` and `AO3CollectionActions.swift`. What is *not*
acceptable is the same endpoint hand-rolled inside a view or a feature folder —
that is the scattering the policy exists to prevent, and it is how the pacer and
the contact UA get bypassed by accident.

Two pieces genuinely cannot be built, for a reason that is AO3's rather than
ours: challenge **matching** (`1cb`, `1cf`) and tag-set **association** (`1ch`)
are not exposed to clients at all. Those want the Open on AO3 escape hatch the
artboards already draw.

**One caveat to state, not to stop for.** The policy's last section notes that
`AO3WriteActions` has never been exercised against a live AO3 session — "a
release gate item, not an agent task". That is a note for the gate rather than a
reason to leave an endpoint unbuilt: write it, hold the
single-shot/no-retry/no-coalesce discipline exactly, and say in the commit that
it is unexercised, as every write already there is.

**The lesson is the one §3 already records twice.** A statement about what the
app does — in a build note, or in this file — is not evidence. Grep for it. This
paragraph asserted a policy that the policy does not contain, cited it as
binding, and stood for three sessions.

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
| `38c42f4` | Codex | Redesign work-card foundation | Claude → `9ee86ba`, re-audited → `1004a81` | 5 spec drifts + 1 hit-target defect found; see §3. **Findings 1–5 verified fixed; finding 6 was still open and had grown a second verbatim copy — paid in `1004a81`.** |
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
| `5a6a12e` | Claude | Serif summary; ON AO3 chips; `SubjectFieldLabel`; page row helpers | unreviewed | **iOS build green.** |
| `f8c2ff6` | Claude | `redesign-spec-inventory.py` — rank shapes by artboard spread | unreviewed | Tooling; ran against the committed canvas. |
| `053bc96` | Claude | `swift-parse-check.py`; batching + parser in §3 | unreviewed | Calibrated: 403/405 files parse clean. |
| `243580a` | Claude | `SubjectForm.swift`; 1a's facts card, tally strip, buttons, My copy row | unreviewed | **iOS build green. Wants a non-Claude reviewer** — it is the shared form family ~50 artboards will be built on. |
| `4d57af8` | Claude | Parts-before-screens in §2; the measured inventory in §1a | unreviewed | Doc only. |
| `d61ad69` | Claude | Tag clusters; inventory table corrected where checking disproved it | unreviewed | **iOS build green.** |
| `cc5a890` | Claude | Retire the section control; My copy sheet; Comments as form rows | unreviewed | **Wants a non-Claude reviewer** — it changes this screen's whole navigation. Red on access levels; fixed in `2e25947`. |
| `6d2b318` | Claude | §3c, next steps; 1a recorded complete | unreviewed | Doc only. |
| `1004a81` | Claude | Audit the Codex review; unify the two identical metadata builders | unreviewed | **Wants a non-Claude reviewer** — it touches `WorkStat`, which every work surface formats through. Unverified tests (CI builds the app target only). |
| `74680bb` | Codex | T-213: locator chapter titles, `@ScaledMetric` accessibility pass, `SensitiveWorkRow` navigation rework, Saved-for-Later split | Claude ✓ (design/logic only) | Committed by the owner mid-session as WIP. Reviewed by reading, not by building: no toolchain here. Call sites consistent, polarity flip complete, parses clean. Its stale-doc updates and ledger rows were missing and are supplied in the commit below. Saved-for-Later split diverges from 1c/1d — kept on the owner's call, recorded in §3. |
| `ca9b158` | Claude | Session durability on background; bound the family-count cache; 5 mutation-checked tests | unreviewed | **Wants a non-Claude reviewer.** Fixes two defects found verifying Grok's layer. Tests unverified — CI builds the app target only. |
| `2e25947` | Claude | Page blocks internal, not private | unreviewed | **iOS build green.** Fixes `cc5a890`. |
| `6d1a08d` | Claude | Tests for `myCopySummary` and the warning figure form | unreviewed | **Unverified by anything here** — CI builds the app target only, so `KudosTests` is never compiled. |
| `5ea4e0e` | Claude | Figure-strip strings as statements | unreviewed | **iOS build green** (10m05s). Behaviour-neutral. **Its commit message states a false reason** — see `40178c3` and §3. |
| `40178c3` | Claude | Correct that message; record the stale-poll trap | unreviewed | Doc only. |
| `725695e` | Grok | Local reading log: sessions, favorites, fandom watermarks; v8 additive backup; reader start/end hooks | Claude ✓ (design/logic only) | Verified by reading, not by building or running. Parse-check clean. **CI has not compiled this.** Tests exist but CI builds the app target only. Manifest stays v8 (Android only accepts 1…8). Not seen on a device. |
| `561f848` | Grok | AO3 collections + challenges networking (`AO3Client+Collections/Challenges`, matching/association are Open-on-AO3 only) | Claude ✓ (design/logic only) | Verified by reading, not by building or running. Writes unexercised against a live AO3 session. `URLSession(` in Services still exactly two constructors. |
| `bac3397` | Grok | AO3 writing-surface networking (work/chapter/series/draft/bulk/tags) + tag autocomplete wrapper | Claude ✓ (design/logic only) | Verified by reading, not by building or running. Reuses `autocompleteTags`; no second URL builder. Writes unexercised. Series create from `/series/new` is Open on AO3. |
| `a0913bf` | Grok | Fandom sibling-family grouping (`1al`/`1am`/`1an`); category work total marked approximate | Claude ✓ (design/logic only) | Verified by reading, not by building or running. Group id is sorted original names, never the parsed title. Not seen. |
| `5100add` | Grok | `includeColor`; searchable language picker; five range sliders; `1ay`/`1az` empty states | Claude ✓ (design/logic only) | Verified by reading, not by building or running. `1ao`/`1aq`/`1as`/`1au`/`1av`/`1aw` confirmed matching code. `1ba` comment-posting note is stale. `1ax` SavedSearch naming+list already exist. |
| `671b7c1` | Claude | Privacy screen on artboard 1ac; measured storage footprint; two bulk clears; `SubjectFormRow.isDestructive` | unreviewed | **Wants a non-Claude reviewer.** Two bulk destructive actions that have never run on a device — the selection rules are tested, the *effect* is not. CI builds the app target only, so the six tests are uncompiled. |
| `cffc1fc` | Claude | Reading Insights on artboard 1bi; `ReadingInsights` rules; `subjectCard`; retires `ReadingStatisticsView` | unreviewed | **Wants a non-Claude reviewer.** A screen was **deleted** (its model and tests survive, its figures moved into a fourth card) — worth a second pair of eyes on whether anything was lost. Thirteen tests, uncompiled. |
| `e7612188` | Claude | Drop the unencoded `fandomUnion`; the CodingKeys rule | unreviewed | **Wants a non-Claude reviewer.** Fixes `5132f943` (not in this ledger). Run on a Mac: the five SavedSearch tests go green. Not run: opening a store written by `39e7eefa` in the app. |
| `769406d7` | Claude | KudosTests compiles; five failures fixed | unreviewed | **Wants a non-Claude reviewer.** New defects in rows marked reviewed: `561f848` (isMatched), `bac3397` (tests never compiled; bulk test pinned the destructive POST). 133/133 in the affected suites. |
| `4ec714ce` | Claude | Codex's named structs for three lint tuples | unreviewed | Codex's own code, ported unchanged. |
| `a0143951` | Claude | macOS target builds; scripts; notices | unreviewed | **Wants a non-Claude reviewer** — touches `project.pbxproj` (one `platformFilter`) and the entitlements check. Debug + Release built on a Mac. |
| `18c95b77` | Codex | Confirm replacement rolling IPA; preserve checkpoint and claim handoff | Claude ✓ | Release asset `Kudos-b0aeeb4.ipa`, target `b0aeeb4111e5b18e3c5cf166a27f5f7c1865ad19`, workflow 34640150956 succeeded. Simulator upgrade verification running; not yet passed. |
| `4465fe02` | Codex | Clamp huge range movements and reset cancelled drags; port approved documentation | Claude → `da8b04d9` | Extracted production arithmetic probe passed at 8×10¹⁸, repeated increments, off-track drags and rounding; Swift parser passed. Full target/UI check pending. |
| `ee82191e` | Codex | Move reader computed helpers into its iOS extension | Claude ✓ | `Scripts/lint.sh` exit 0; struct is now 899 non-comment lines. No stored properties moved. Simulator behavior still pending. |
| `da8b04d9` | Claude | Finish T-215.1 (upgrade check); review Codex's T-215 commits; NaN guard in `offsetValue` | unreviewed | **Wants Codex's review** — as do `e7612188`, `769406d7`, `4ec714ce`, `a0143951` above. |
| `a01c857c` `996cef24` | Gemini 3.1 Pro | 1l Inbox, 1z Preferences, 1bb saved state | Claude → `40250315` | Implemented under orchestration. 1z was half-restyled (no header, kept its nav title under a wash that empties it, bare `ScrollView` without the themed scroll/rows), its footnote described rows the app lacks, and it carried a lint error, 15 warnings and trailing whitespace despite the commit claiming SwiftLint passed. |
| `d8a7192b` | Gemini 3.8 Flash | 1aa More on AO3, with the archive section | Claude → `40250315` | Implemented under orchestration. Clean: matches 1ac's shape and the artboard's own header and seven row titles exactly. Fixed: a footnote describing the section above it, and a force-unwrapped URL. |
| `40250315` | Claude | Review fixes on the Gemini batch | unreviewed | **Wants Codex's review**, with the five Claude commits above. |
| `aab42504` | Claude | The family union, through `filter_ids` | Codex → `bb6e6d0f` | **Wants a non-Claude reviewer.** Measured against live AO3 rather than reasoned about — the third attempt at this, and the first with numbers. |
| `1b37613c` | Codex | Assignment matching from real paged AO3 markup | Claude ✓ | Answers the defect recorded on 2026-09-11: the parser now reads otwarchive's real dt/dd maintainer templates and pages every tab through the coordinator. Production maintainer reads stay unexercised — the index needs an account that maintains a collection. |
| `4443ac8c` | Codex | Shared writing editor, native drafts (1x), entry points | Claude → `d9ec7855` | Sound where it matters: CSP `default-src 'none'`, every navigation but about:blank cancelled, non-persistent store, and rich mode refuses any document it cannot represent (so an `<img>` chapter never renders). Two defects fixed: unbounded recovery copies, and unpublished writing missing from the Privacy screen's measured figure. **Architecture note for the owner below.** |
| `d9ec7855` | Claude | Bound recovery copies; count them in the footprint | Codex → `bb6e6d0f` | Bounds are sound; connected the missing Privacy row. |
| `2d5245a3` | Gemini 3.1 Pro | 1bn, 1bo, 1bp, 1bq writing screens | Claude ✓ | No new URLSession, reuses AO3WorkActions, keeps the non-destructive bulk-edit rule, correct wash/cardList order. Left three lint-manipulation scripts uncommitted in its worktree (third time for this model); none reached the branch. **Screens are not yet reachable from navigation.** |
| `b3422c7a` `b8b66373` `409c6f18` `d41df8bc` | Gemini 3.8 Flash | 1bx, 1ce, 1by, 1bz, 1ca challenges | Claude ✓ | Open-on-AO3 for matching as the spec requires, three confirmations on irreversible writes, and it degrades to "No assignments found" rather than trusting the known-broken assignments parse. **Not yet reachable from navigation.** |
| `3eeabd89` `d0526c0e` | Gemini 3.8 Flash | 1k switcher pill; 1d collection ledger row | Claude → `7433b052` | Faithful to the artboard's measured tokens; affordances one for one; miniature covers filtered through `passesPrivacy`. Fixed: a helper the change orphaned, and an unexplained grey. |
| `578a0bac` | Gemini 3.1 Pro | 1u Works, 1v filter, 1w Series | Claude → `6b6c8ae6` | Its run died mid-session: the commit did not compile, it had stubbed `Scripts/swift-parse-check.py` (refused), suppressed a lint rule (reverted), mis-credited its own model, and its chip rail dropped VoiceOver's selected state. 1x Drafts is NOT built. |
| `bc2e83c8` `80562550` `4bd27c0e` `eff63fa8` | Sonnet | 1h queue detail, 1i organizer, 1j new queue, 1bg select mode | Claude → `6b6c8ae6` | The strongest of the three: every claim it made checked out (affordances 2→4 swipe, 7→7 labels, preservation UI intact), and it refused 1bh with its reasoning in code rather than faking a feature. Fixed: AccountView's lint error surfaced by the merge, and a dark-only gradient. |
| `1b37613c` | Codex | Parse actual assignment templates and join every page, including open assignments | unreviewed | 8/8 AO3ChallengeParsingTests pass on iOS 26.5; lint exit 0. Maintainer-only parser remains unexercised against production. |
| `bb6e6d0f` | Codex | Resolve fandom IDs from authoritative feed controls or exact sidebar labels; display draft recovery bytes | unreviewed | 1,777 iOS tests passed; macOS Debug/Release built. Expected ad-hoc product-signing gate remains. Internal source review only; Privacy screenshot remains manual. |
| `30b268bb` | Codex | Replace the web editor with native HTML text controls and undoable tag/recovery insertion | unreviewed | Internal review only. 1,777 iOS tests passed; macOS Debug/Release built; expected ad-hoc product gate. Four themes inspected, including Accessibility Large. |
| T-215 writing-model cleanup (this commit) | Codex | Correct bulk tag semantics in documentation; remove unused overwrite helpers | unreviewed | Focused parser/payload tests, macOS Debug build, lint and whitespace pass. No payload behavior changed. |
**Family names to use:** `Claude`, `Codex`, `Grok`, `Gemini`, `Human`.
Version numbers are welcome in Notes but the family is what gates rule 1.

---

## 3. Status log

Newest first. Each entry: what landed, what it was verified against, what is
left. Keep appending — this is the handoff channel.

### 2026-09-13 — Correct bulk-edit model documentation (Codex)

Handoff item 7: documented that native tag additions/removals require per-work
merge-and-replace, while uniform scalar changes use the bulk endpoint. Removed
the orphaned chip comment and unused `overwriteFieldKeys`/`isOverwriteField`
helpers (no production callers), along with their two tautological assertions.
Existing tests still check the actual uniform POST and per-work merged lists.
Focused AO3WorkFormParsingTests pass; macOS Debug builds; lint and whitespace
pass. No network writes or payload behavior changed.

---

### 2026-09-13 — Native writing buffer and tag toolbar (Codex)

Followed the owner's native-UI requirement recorded in the remote handoff:
`WritingTextEditor` now mounts `UITextView` on iOS and `NSTextView` on macOS.
The HTML buffer is the source of truth; the toolbar inserts literal tags around
the native selection, with native undo/redo. Removed the two WebKit editor
implementation files. Existing work/draft/chapter routes and their AO3 save
boundaries are unchanged. Recovery restoration is undoable; Done and back flush
synchronously, without an asynchronous web snapshot racing dismissal.

The native-control test passed for exact unsupported HTML/Unicode preservation,
selection wrapping, ordinary event-driven undo/redo, recovery undo, and iOS
marked-text composition flushed on Done. Pure tests cover tag/link insertion;
existing account/session recovery tests remain. Source adversarial review found
no further defects. This is an internal Codex pass, not cross-family approval.

Inspected hosted SwiftUI editor screenshots in Light, Sepia, Dark and OLED
(`/tmp/kudos-native-screenshots`); OLED uses Accessibility Large. Text, Undo,
Redo, Done and the horizontally scrolling tag bar remain readable without
clipping or overlap. Full iOS harness `/tmp/kudos-native-full.xcresult`:
**1,777 passed, zero failed, two skipped**. Invariants and lint pass;
`build-macos.sh` builds Debug/Release and fails only the existing ad-hoc Release
product signature check. Whitespace passes. Live AO3 saves, physical keyboard/
VoiceOver and macOS editor interaction remain manual.

---

### 2026-09-13 — Resume at the new remote tip; finish fandom ID fallback (Codex)

Fast-forwarded `4443ac8c` to `9a0d455e`, retaining Claude's editor review,
recovery bounds, and all intervening card/wash changes. T-215's remaining family
union work was a real gap: `AO3FandomUnion.filterID` documented a sidebar fallback
but never used `tagName` and only scanned the whole HTML for a feed URL.

The parser now reads feed controls, then the exact fandom's include-checkbox
inside `#work-filters`. It removes only the final work-count suffix from the
label, preserving years/parentheses in the fandom name and decoded entities.
Quoted feed URLs in work prose and feed links on other hosts do not resolve the
family. The existing all-or-nothing union, coordinator, bounded ID cache and
filter serialization are unchanged. Four regression cases cover these paths, including AO3’s nested RSS navigation control.
The fixture structure was checked against otwarchive's
[works filter template](https://github.com/otwcode/otwarchive/blob/master/app/views/works/_filters.html.erb)
and `tags_helper.rb#label_for_filter`; no production writes were sent.

Review of `d9ec7855` found its new recovery byte counter was never displayed:
`PrivacyDataView.storedSizeRows` still ended at Caches. Added the missing Draft
recovery row using the same measured byte formatter and form row. Pruning stays
unchanged; the existing per-copy delete remains in the recovery chooser.

Verification: final full iOS harness `/tmp/kudos-fandom-final-20260913.xcresult`
passed **1,777 tests, zero failed, two skipped**. Invariants and lint passed;
macOS Debug and Release both built. `verify.sh` stopped only at the expected
Release product check, “Release product is still ad-hoc signed”; no signing
settings were changed. Whitespace passed separately. Internal adversarial
source review found no further defects; cross-family review and visual checking
of the new Privacy row remain manual. No AO3 writes were sent.

Next: follow the native-UI requirement recorded in Claude's handoff below by
replacing the writing editor's web surface with native text controls and a
markup-inserting toolbar. Remaining handoff work stays tracked under T-215.

---

<a id="account-subsection-audit-2026-09-14"></a>
### 2026-09-14 — T-219 Account subsections: rendering-path audit (Codex)

**Pass 1, before UI changes; baseline `3d1a46a4`.** This table supersedes
the Phase 5/6 completion summaries above and earlier claims below for these
18 boards. Read each with `Scripts/redesign-spec-outline.py --board <id>`
and its `--notes` rationale. The canvas's actual element tree wins over a
stale prose note. No signed-in screen was visually inspected: this simulator
cannot sign into AO3. “Built” means source structure and redesign vocabulary
are present, not a visual sign-off. Paths below are under `kudos-ao3-reader/`.

The hub selects scopes and renders content inline. Its `onRefine` pushes a
second list. A redesigned header on that pushed list does **not** establish
that the subsection reached from the hub has been built.

| Board, in hub order | Pass-1 verdict | Rendering evidence and exact gaps |
|---|---|---|
| **1o Marked for Later** | **Partially built** | `AccountView.readingSections` / `compactWorksContent` → `AccountComponents.AccountWorksInlineSection`: plain `Text` section header, standard `SensitiveWorkRow` / `AO3WorkRow`, or a uniform compact grid. `AO3AccountWorksList.worksList` (the Refine push) has `SubjectHeaderBlock`, `subjectScreenWash`, ledger cards and `cardList`. Missing on the actual subsection: its own hero/tally/chrome, All/Updated/Downloaded/Reset pills, updated-cover group followed by Everything else ledger group with `SectionRuleHeader`, new-chapter range badge, downloaded-size line and AO3-unmark explanatory footer. No last-sync timestamp is held by this view. |
| **1q Bookmarks** | **Partially built** | Hub → `AO3AuthorBookmarksSection` → `AO3AuthorBookmarkRow` or `AccountBookmarksCompactGrid`. The detailed row calls standard `AO3WorkRow`, then separate recommendation/private/date badges, `TagChip` tags and a plain labelled notes block. Missing: subsection hero with cached tally, All/Recs/Private/With notes/Reset rail, fandom-washed search-ledger card treatment, accent-rail bookmark note, private lock chip in the card header, bookmark date at the metadata trailing edge, distinct AO3 bookmark tag pills and explanatory footer. Existing notes/tags must survive the restyle. |
| **1t History** | **Partially built** | Hub → the same `AccountWorksInlineSection` standard rows/grid; pushed Refine → `AO3AccountWorksList` header/ledger. Missing: History's own Activity header/chrome, Everything/In progress/Finished/Reset pills, time-group rule headers, remote visit/version/marked-for-later/skip information, local-progress pairing in the drawn history row, Delete-from-History swipe and confirmed Clear in overflow. Current view parses the generic works page, not a history-specific record projection. Local Library history is a different screen. |
| **1p Subscriptions** | **Partially built** | Hub uses `AccountWorksInlineSection`, which has no watermark logic. The separate pushed `AO3AccountWorksList` uses `SubscriptionWatermarks` and overlays NEW only on detailed rows; compact cards receive no badge. Missing: Works/Series/Authors/Reset pills, New-since-last-looked cover group with chapter ranges, All works ledger group, unsubscribe swipe, own hero and caller-aware Home/AO3 Account kicker. Sparse subscription blurbs do not supply chapter totals; do not fetch to populate the drawn global “7 with new chapters.” |
| **1r Collections — items as a scope** | **Partially built** | `AO3CollectionsList` has `SubjectHeaderBlock`, `SubjectFilterRail`, `SubjectChip`, `pageBodyRow`, `cardList`, wash and New/Filter tools. `AO3CollectionCard` uses one account palette and title-first layout. Missing: Collections/Your items scope pills and cached pending badge, account-wide items destination, each collection's hue/archive-box tile/owner eyebrow, approval and own-work facts, trailing date and Edit/Delete swipes. Existing edit/manage actions are context-menu entries; Delete remains AO3-owned. The list currently loads page 1 only. |
| **1s Collection items** | **Partially built** | Contrary to the old tracker, `AO3CollectionItemsView` and `AO3CollectionItemStaging` exist: `SubjectHeaderBlock`, segmented approval tabs, collection kicker/role, work title, labelled approval/switch rows, explicit removal, staged submission, panels and wash. Missing: account-wide scope reached from 1r (constructor requires a collection slug), Reset, visible toolbar staged count (currently in subtitle/accessibility label), item date and pagination (fetch fixed to page 1). Existing staging across a tab reload also needs careful verification before expanding this screen. |
| **1u Works** | **Partially built** | `AccountView.writingSections` detailed branch draws `EnrichingAO3WorkRow(.searchLedger)` plus Edit swipe; compact branch follows different `AO3AuthorWorksSection` code. Missing: own Works hero/tally, Works/In collections/Gifts sibling scopes, complete per-work performance strip in the detailed Account branch, Tags/Add Chapter/Delete swipe actions and bulk Edit Works entry. Existing generic filters only affect the detailed branch. The hub's posted/unposted groups (1bt) are not substitutes for this screen. |
| **1v Works sort/filter** | **Partially built** | Actual funnel → `AO3FilterPanel(mode: .refine)` in `AccountView.body`. This is the shared themed refine form, not the drawn Works sort/filter sheet. Missing: nine-field sort menu and direction (refine hides them), server-backed include/exclude facet groups/counts, other-tag fields, crossovers, updated bounds, search-within-results, query application and active funnel count. Completion/tags/rating/language/word-count refine capability exists but does not establish artboard completion. |
| **1w Series** | **Partially built** | Hub → `profileSeriesSections` → `AO3AuthorSeriesSection` / `AO3SeriesRow(.ledger)`. Empty state uses `subjectPanel`; ledger has an icon, hand-drawn fandom/rule, complete badge, summary, works/words. Missing: subsection `SubjectHeaderBlock`, cache-backed Series tally (dashboard count currently discarded), true spine-stack treatment, restricted badge, inline running order, bookmarks/revised metadata and Edit/Reorder swipe destinations. Ledger hard-codes white text and loses existing byline/date metadata. |
| **1x Drafts** | **Partially built** | Hub link → `WritingDraftsView`: `cardList` and wash, but bare New-work row, title/fandom-only draft links, previous/next HStack, no redesigned hero. Missing: header/cached draft tally, draft-specific washed rows with kicker/rule/title/summary, rating/warning/category signals without completion, chapter/word/created metadata, expiry chips and expiring-week tally, switcher paging. **Post/Delete deliberately excluded by owner instruction; retain the existing deferral note.** Existing warning correctly says **30 days**, not the drawn 29. |
| **1l Inbox** | **Partially built** | Hub Activity → `AccountInboxRows`: header, `subjectPanel` + `SubjectRowSeparator`, Reply/Replied and `SearchPaginationBar` exist. Missing: All/Unread/Awaiting reply/Replied rail with pinned dashed Filter; awaiting-reply tally; inline Mark read/unread (only in overflow); own-reply quotation/rail; settled-shell overflow and standalone Activity composition instead of stacked hub furniture. Source has parsed AO3 Inbox form read/unread writes (`AO3InboxModel`), contrary to the stale rationale's “device-side only”; retain that real behavior. |
| **1y Dashboard** | **Partially built** | `AO3DashboardView` wraps `AuthorProfileView`; own detailed works receive `SubjectStatStrip` via `AO3AuthorWorksSection`. Actual profile still has a card hero, native segmented picker and one selected content tab at a time. Missing: AO3 Account subject header/wash, joined/pseud/invitation facts in the drawn header, recent works + recent series + recent bookmarks together, ruled group headings, See-all links and header New-work action. One existing performance strip is not the dashboard artboard. |
| **1z AO3 Preferences** | **Partially built** | `AO3PreferencesView.formContent` has header, parsed toggle groups, `SubjectFieldLabel`, `SubjectFormRow`, help buttons, separators/panels, `cardList` and wash. Missing: Account links (Edit profile, Manage pseuds, username/password/email, blocked/muted), section disclosure chevrons, drawn Site skin vs Locale/format grouping (select/text controls currently one Display options group), explicit reading-history-clear warning. Success has a checkmark but is an in-flow banner, not the transient toast described by the related saved-state board. Do not invent preference fields absent from the real parsed form. |
| **1ab Settings** | **Not built** | Hub gear → `ReaderOptionsForm(includeAppSettings: true)` in `Settings/SettingsView.swift`. It is a native Form with `.appThemedRows`/`.appThemedScroll` and one new caption; no subject header, section-rule/panel/form-row redesign. Missing: the entire artboard composition, Reading-first groups, inline About version/account/privacy/sign-out block, measured storage row. Existing theme/font/size controls work but do not establish a built board. Download-on-subscribe, keep-downloads duration and three notification switches have no established matching behavior here; preserve all existing backup/sync/import/privacy/TTS options in any redesign. |
| **1ac Privacy/local data** | **Partially built** | `PrivacyDataView` matches header/promise/stored/clear panel structure using all form primitives; measurements and confirmations already exist. Missing: destructive styling on clear rows; Browse-cache clear bypasses confirmation despite the footer promising every clear asks first. Search-history count/clear intentionally absent because no log exists (saved searches are user content). Retain voice-pack/session/recovery disclosures; “AO3 and nothing else” in the artboard is contradicted by optional voice-pack downloads. |
| **1aa More on AO3** | **Partially built** | `AccountMoreOnAO3View` uses header/rule headers/panel/form rows/separators/wash. The archive's seven rows match. Missing: Post and manage group (Post new, Import, bulk Edit, Manage items, Related works), Your account group (Profile, Invitations, Skins, Fannish next of kin), drawn group ordering and cache-backed available counts. Current Creator tools = Drafts/Pseuds/Skins/Statistics; Challenges also contains unrelated Co-Creator/Related works rows. Links open Browse; header currently says “browser.” Do not drop existing useful destinations. |
| **1n Signed-out preview** | **Partially built** | `AccountView.standardListRoot` correctly omits wash and `signedOutPreviewSection` uses rule headers, real destination rows, panels and a fade. Missing: preview avatar/username skeleton and Reading/Writing/Activity scope pills; signed-out identity is duplicated by an extra accent `SubjectHeaderBlock` above `AccountProfileCard.signedOut`. The board asks for neutral Not signed in / No account, no colour, one identity, and a neutral login/gear treatment. |
| **1k Paging pill/page sheet** | **Partially built** | `SearchPaginationBar` and `PageJumpSheet` implement the pill, accent-next, field, ten nearby tiles, First/Last and staged confirmation with `GlassCircleButton`. No structural gap in the requested paging portion. Remaining gap: pill arrow/centre targets are 32pt, end buttons 42pt, below the 44pt minimum already established on this branch; sheet has one fixed 430pt detent and no scroll fallback for large text/keyboard. Treat drawn chrome dimensions as artwork, not accessibility authority. Search-results content is outside this task's paging scope. |

**Pass 2 order:** smallest complete gaps first: 1k, 1ac, 1n, then the
remaining boards after estimating their data/navigation work. A board is not
declared complete by adding only its header. Each UI commit must name its
board, record deliberate omissions and pass lint + the requested iOS Debug
build. Full raw `xcodebuild test` at the end is explicitly requested by the
owner against the 13-failure baseline, superseding the usual case-fold harness
instruction for this task. No push or merge. Cross-platform and visual claims
require their own evidence; signed-in screenshots remain unavailable.

**Audit gate:** lint exit 0, no `error:` output; XcodeBuildMCP iOS Debug
build succeeded using the specified worktree/project/scheme/simulator/DerivedData
(2026-09-14 13:29 UTC). The shell invocation of the requested build failed
before compilation because its sandbox could not access SwiftPM cache paths
or CoreSimulator; the purpose-built Xcode tool completed the same build.

**1y visual gate, closed 2026-09-15 (Claude).** Codex could not run it —
it reached for Computer Use and was refused Simulator access — so the
Dashboard was inspected here instead, on the simulator signed into a live
account, via `xcrun simctl io <udid> screenshot`. Confirmed on screen at
`50b215de`: floating back/overflow chrome, the AO3-Account kicker and rule,
the username as the page title, a New work action in the header, and
**Fandoms, Recent works, Recent series and Recent bookmarks all present at
once**, each a `SectionRuleHeader` carrying its real count and a See-all
link. The card hero and the native segmented picker are gone, and the
per-work performance strip renders inside the card. Recent series shows its
empty state rather than a fabricated row; bookmark notes survive the
restyle. Codex's own commit records what it left out and why, and states
that 1u and 1w still need their own scopes, actions and running-order
presentation — their new headers are not parity.

<a id="sweep-findings-2026-09-15"></a>
**Sweep findings, 2026-09-15 (Claude, verified from source — not taken from an
agent's report).** A Codex audit pass of the 69 non-Account boards stopped before
writing its table; it surfaced two claims, both checked here against the code.

**1ah / 1ai Reading History — the app's "History" is a different thing wearing
the same name. CONFIRMED, and larger than a layout gap.** `LibrarySectionKind`
selects `.history` as `!hasEPUB && !isQueuedForLater` — works whose EPUB was
*freed* after finishing. A work you have read and still have downloaded never
appears. 1ah is explicit that this is *"the local one, not AO3's"* and that it is
**"Entirely new. Needs a local reading log"**: last-read chapter and timestamp per
work, cumulative time spent, a reread count that increments on finishing again,
and the chapter count at your last visit so "changed since" can be computed. 1ai
adds an Abandoned state *derived* from that log (mid-way and untouched past a
threshold) with a manual override so the threshold cannot re-abandon it. None of
that data is stored today. This is a persistence model, not a screen: it needs
its own design pass, and building the ledger rows over the existing `!hasEPUB`
partition would put the artboard's chrome on the wrong set of works. **Not
started deliberately.**

> **CLOSED 2026-09-15 — and the "not stored today" above was already stale when
> it was written.** The log exists: commit `725695e` added `ReadingSession`
> (which stores `durationSeconds`, `didFinish` for the reread count, and
> `chapterCountAtVisit` commented *"for 'changed since' (1ah)"*) and
> `ReadingLogService` (whose `defaultAbandonedThreshold` is commented *"1ai
> default"*). The screens exist too — `LibraryHistoryGrouping` (Time / State /
> Fandom / Flat), `ReadingHistoryFactsStrip`, `ReadingAffinities` and
> `FavoriteAffinityRow` — as the Phase 9 table records. What was genuinely still
> wrong was one line: `LibrarySectionKind.history` still selected `!hasEPUB`, so
> the right chrome was drawn over the wrong set of works, and 1ai's **Abandoned
> bucket was unreachable by construction** — `isAbandoned` requires
> `isInProgress`, which requires the EPUB that `!hasEPUB` excludes.
> `LibraryHistoryGrouping` had found that overlap and documented it rather than
> fixing it, correctly declining to redefine the shelf from inside a grouping
> helper. The predicate is now `hasStartedReading || isFinished`, ordered
> most-recently-read (the time buckets assume that sort).
>
> The lesson is the one this plan keeps paying for: **a blocker is a claim with
> a date on it.** This one survived several ticks of a sweep purely because it
> read like a settled fact and nobody re-grepped for the model it said was
> missing. Re-verify a blocker before routing around it, exactly as a "done"
> gets re-verified before being trusted.

**1aj Favorites — Works is the one board in this group still short, 2026-09-15.**
The scopes, the affinity aggregates and the ordering are all built. Three things
in 1aj's own line are not:

1. **The Rereads and Offline chips.** Offline is free (`hasEPUB`). Rereads is
   `finishCount > 1`, which only `ReadingLogService.summaries(in:)` knows, and
   that call fetches the whole session table. `visibleItems` is referenced about
   ten times per render, so filtering inside it would fetch the log ten times a
   frame. `WorkReadingSummary` is a plain derived struct, not a `@Model`, so
   there is no `@Query` to lean on, and an unconditional `@Query` over
   `ReadingSession` would load the log for all seven sections — the exact cost
   the existing gate in this view was written to avoid.
2. **The reread count on the row footer.** `ReadingHistoryFactsStrip` already
   draws it but is gated to History and also draws duration and new-chapters,
   which 1aj does not ask for. Needs a style parameter, not a second view.
3. **The filled star beside the title.** Sanctioned in advance: the note above
   on the removed glyph slot says 1t and 1aj "can re-add the pair when one of
   those is built". Note the removal that was *explicitly approved* was the
   offline tick, not the slot — so re-adding the slot for the star is in scope,
   but re-adding the offline tick that 1aj's line also mentions is **not**,
   because the owner approved its removal as a density reduction.

The blocker on (1) is that the fix wants `visibleItems` computed once per render
and threaded, and this view is 703 lines — the file class where adding an
`if`/`else` in a closure or a multi-argument modifier closure makes the Swift
type checker stop terminating rather than fail. Do it as its own change with a
build after each step, not as a rider on something else.

> **BUILT 2026-09-15 — and reading the artboard tree corrected the write-up
> above twice.** Both corrections came from the element tree, not the prose note:
>
> - The rail is **single-select with four chips — All / Rereads / Offline / WIP**,
>   All carrying the solid accent. The BUILD note names only "the Rereads and
>   Offline chips", so a note-only read produced two independent toggles and
>   missed WIP entirely. The prose says what a screen is *for*; only the tree says
>   what is on it.
> - The footer is **duration *and* reread count** — "6h 42m · Read ×3". 1aj drops
>   only the changed-since fact, so `ReadingHistoryFactsStrip` took a `.favorites`
>   style rather than the "reread alone" one the note above predicted.
>
> Also settled from the tree: **"Read ×N" is `#F2C879` on both 1ah and 1aj,
> whatever the card's own accent** — on 1ah it sits on a card accented `#7FC9E0`
> and stays gold. It is the one mark in the ledger row deliberately *not* taking
> the card's hue, because it belongs to the star rather than to the fandom, so it
> is `Color.subjectFavoriteGold` and not `palette.accent`. That is a genuine
> exception to the owner's "accent from the card colour" rule, not a miss.
>
> The star went in through a re-added `WorkLedgerRow.titleSymbol` /
> `titleSymbolTint` pair — on the *title* line, where 1aj draws it, not back on
> the metadata line the removed pair sat on. It is gated by a `showsFavoriteStar`
> flag rather than read from `work.isFavorite`, because 1ah and 1ai draw no star:
> it marks the screen that is about favourites, not the state of being one. The
> offline tick 1aj's prose also names stays gone, per the approved reduction.
>
> Not built: 1aj's dashed **Sort** chip. This screen already carries
> `filterChipRail`, whose pinned dashed chip opens the panel that owns both the
> filters and the sort order, and two ways to set one value is worse than one in
> a different place. `FavoriteQuickFilter` is its own testable value with four
> cases pinned by `FavoriteQuickFilterTests`.

**1ak's newest-work line: the stated blocker is stale, but the real constraint is
different and worth deciding before building, 2026-09-15.** 1ak's BUILD note says
the line "needs the author page parsed, which the app does not do yet". The app
does: `AO3Client+Authors.parseAuthorWorksPage` parses an author's works page, and
`AO3AuthorProfileService` already exposes `works: [AO3WorkSummary]` from it. That
is the **third** stale claim this sweep, after 1ah/1ai's reading log and the
Phase 9 table's own "not stored today".

The genuine constraint is cost, not capability. 1ak draws one row per author — the
artboard shows nine — and each newest-work line is a separate fetch of that
author's works page. Nine requests to paint one screen, against a site that rate
limits, is not a thing to do on appear. Before building this, decide: fetch lazily
per visible row, cache with a TTL like `AO3AccountListCountsCache`, or only on an
explicit tap. The per-author aggregation the same note asks for is already done
(`ReadingAffinities.authors`), so the line is all that is left.

> **BUILT 2026-09-15.** The fetch strategy turned out to be mostly decided
> already: `AO3AuthorProfileFetcher.page` caches HTML per URL and auth scope and
> runs inside `AO3RequestCoordinator.withSlot`, which caps concurrency, and it
> falls back to stale HTML on error. `AuthorNewestWorkStore` adds only a parsed-
> answer cache with a 30-minute TTL, and the fetch is per-row in `.task`, so N
> authors cost N requests only if N rows are actually looked at.
>
> **Two things the artboard says that the app cannot honestly say.** Both were
> probed live on 2026-09-15 rather than assumed:
>
> - A user's works page defaults to `revised_at` (**Date Updated**) — confirmed by
>   the selected `<option>` in the live markup — so its first row is the most
>   recently *edited* work, not the newest. The request now pins
>   `work_search[sort_column]=created_at`; that URL returns 200 and reports "Date
>   Posted" selected.
> - The artboard's line reads "posted 2 Sep 2026". A works-page blurb carries one
>   date and the parser stores it as `AO3WorkSummary.dateUpdated`, because that is
>   the date AO3 prints there. **The app writes "updated".** The *ordering* is by
>   date posted, which is what decides which work the line shows; the label is the
>   date the app actually has.
>
> **A byline is not a username.** `ReadingAffinities.Row` gained `username`,
> resolved from `SavedWork.verifiedAuthorIdentities` rather than parsed out of the
> byline — AO3 bylines point at pseuds, and `/users/<pseud>/works` is not that
> account's works page. An orphaned, anonymous or hand-imported work has no
> registered identity, so those rows simply draw no newest-work block.
>
> Also built: the 38pt tile at its real per-scope shape (authors and tags are
> circles, fandoms a rounded square — not derivable from the existing
> `usesHashTile` flag), and the filled gold star the spec draws on every row of
> all three scopes. The star is not a toggle: `ReadingLogService.setFavorite`
> still has no callers, and these scopes are *derived* favourites, so drawing a
> tappable star would imply state nothing writes.
>
> **Dropped, and it is the spec's call not mine:** the Authors rows no longer show
> the library line ("N unread works in your library"). 1ak replaces it with the
> newest-work block and its own label says the counts belong on the author's page
> "rather than crowding the row". Fandoms and tags keep it. One line to reverse if
> that reads wrong on a real library.
>
> **Not built:** (a) the row's trailing chevron to the author's own page — Library
> registers no author destination and adding one means touching `LibraryView`,
> the view whose type checker stops terminating; (b) the "With new work" chip.
> That one is not laziness: it filters on a fact fetched per visible row, so the
> answer is unknown for every row not yet on screen, and a filter that silently
> omits unfetched rows is worse than no filter. It needs all rows fetched up
> front — the fan-out this design was built to avoid — or a different definition.

<a id="search-turn-audit-2026-09-15"></a>
**Search turn (1al, 1ao–1ax) audited 2026-09-15 — nine of eleven boards were
already built, and five spec notes are themselves stale.**

Notes that say **"Matches the code"** and do: `1ao` (medium detent), `1aq`
(status/dates/language), `1as` (tag fields), `1aw` (typing with a selection).
Notes that say **"Needs building"** for work that is already done: `1ap` —
`SemanticThemeColors.includeColor` exists, resolving through
`statusSuccessColor` with the exact rationale the note argues for, and both
strikethroughs are in place (`AO3FilterPanel:370`, `TagSelectField:253`); `1ar`
(`FilterLanguagePicker`); `1at` (`FilterRangeSlider`); `1ax` (`SaveSearchSheet`
plus the `SavedSearch` model); `1al` (`FandomFamily`, commit `a0913bf6`).
**1ap was additionally confirmed on screen** — the included row draws tinted
green with a filled plus, plainly distinct from the app's red accent.

Built this tick: **1au's live count.** The panel took no loaded works at all, so
"the count updates live above the form" had nothing to count. `AO3FilterPanel`
now takes `refineSource` and `AO3AccountWorksList` passes the same array
`visibleWorks` narrows, so the line and the list cannot disagree. Verified on the
simulator: "14 of the 14 works on this page match", then "1 of the 14" on
including one warning, then back on Reset. Also **1av's no-fandom copy**, which
fell through to the same bare "Type above…" that a failed suggestion load shows.

**Found in passing, NOT fixed — `AccountView` has a Refine panel that filters
nothing.** `AccountView.filters` is declared, handed to an `AO3FilterPanel` in
`.refine` mode, and never applied to anything; the works list it used to narrow
now lives in `AO3AccountWorksList`. Its toolbar button is gated on
`selectedTab == .writing && writingTab == .works`, so whether it is reachable at
all is an Account-turn question. Left alone deliberately: deciding whether that
hub still owns a works list is that turn's call, and `AccountView` is one of the
views whose type checker stops terminating. The new count line does not appear
there — `refineSource` defaults to empty — so nothing on screen lies about it.

<a id="browse-turn-audit-2026-09-15"></a>
**Browse turn (1g, 1am, 1an) audited 2026-09-15 — all three notes say "Needs
building" and all three were substantially built.**

`1an` is `FandomListFilterSheet`, with the three parser switches (`rpf`,
`allMediaTypes`, `relatedFandoms`), minimum works, favourited and downloads, each
carrying the count it would remove. `1am` is `FandomFamily` + `FandomFamilyRows`
(commit `a0913bf6`), including the tilde on a summed family figure and the logic
that drops it once a family has been opened and AO3 has answered with a
deduplicated total. `1g` is `MediaBrowserView`, whose own doc comment already
answers that board's build note: AO3's featured subset is not parsed, but the app
caches the whole per-category list with a work count on each, so the cluster shows
the largest fandoms — no new request, and a better list than a hand-curated one.
`1am`'s "the same fix applies a level up" is done too: the category header prints
`~3.6M works` with the tilde, via `isApproximateWorkCount`.

Built this tick: **1g's second requirement, the `FandomDisplayName` split on the
cluster chips.** They were drawing the raw AO3 tag at `lineLimit(1)`, so the
panel read "僕のヒーローアカデミア | Boku no Hero Aca…" and
"Pocket Monsters | Pokemon - All Media Typ…" — truncated mid-word, and the two
One Piece tags were separated only by text past the cut. The chip now takes a
split `title` + dimmed `qualifier`, computed once in `computeStats` (already off
the main actor) rather than per render. Identity is untouched: the tap still
sends `fandom.name`, because splitting is not reversible.

**The screenshot caught what the build could not.** Reusing
`FandomQualifier.displayText(parts:fallback:)` with the nested-member-row's
`fallback: split.title` made every unqualified chip repeat itself —
"Haikyuu!! Haikyuu!!", "Attack on Titan Attack on Titan". The fallback is correct
where it came from (a member row under a family title that is printed once needs
*something* to name it) and wrong in a standalone chip, where the title is
already the first word. Passing an empty fallback fixes it. Verified on the
simulator before and after.

<a id="queue-turn-audit-2026-09-15"></a>
**Queue turn (1h, 1i, 1j) audited 2026-09-15 — the gaps here are the data model,
not the layout, and three files had already said so.**

`1h` carries no BUILD line at all; it is a pure description. `1i` and `1j` say
"Needs building", and the screens exist — `ReadingQueueBrowser`,
`ReadingQueueOrganizer`, `ReadingQueueSettingsView`, `NewReadingQueueSheet`. What
they lack is schema. `ReadingQueueOrganizer`, `ReadingQueueSettingsView` and
`NewReadingQueueSheet` each carry a careful doc comment listing what its artboard
draws that it does not build and why, and all three reduce to the same sentence:
`ReadingQueue` has no tags, no pin flag, no per-queue download policy, and no
stored colour. Each note was right to stop where it did — those were restyling
tasks. This sweep is chartered for missing functionality, so the schema change is
in scope now.

Built this tick: **the stored colour** (`ReadingQueue.hue`), which 1h and 1j both
name explicitly — 1j calls it "stored, not hashed from the name" and 1h says
"every accent ... is the queue's stored hue". It fixes a real defect on the way:
the colour was `CoverArt.hue(for: queue.displayName)`, so **renaming a queue
silently repainted it**. `displayHue` falls back to that same hash when `hue` is
nil, so every existing queue keeps exactly the colour it had and the addition
needs no migration. `QueueHueSwatches` holds 1j's five swatches as hues rather
than the mock's hex, so one swatch means the same thing under every theme.
Backup carries it as an optional field — additive, no version bump, and the merge
only ever fills a colour in, never clears one, so an archive written before this
(or by Android, which does not write it) cannot strip a colour the reader picked.

**The simulator found a duplicate nobody knew was there.** The swatches did not
appear, through two clean reinstalls. `NewReadingQueueSheet` exists precisely to
replace the "near-identical plain `Form`" the organizer and browser each had —
but **Home had a third copy**, inline in `HomeView`, never migrated. So Home's
New Queue card silently missed every improvement made to the shared sheet. Home
now uses it: one sheet, three entry points.

Not built, and each needs its own schema decision: queue **tags** (1h's "+ Tag",
1i's tag rail and "Edit tags"), a **pin** flag (1i's Pinned section, currently
stood in for by Saved for Later), a per-queue **offline** policy (1h.3's "Keep
works offline" — today every queued work is preserved, so the toggle would offer
a choice the app does not have), and 1j's **seed step**. Also 1i's
cross-queue/tag/work search, which has no search behind it anywhere in the app.
One more is now merely stale rather than blocked: `ReadingQueueSettingsView` says
a "Last read" row would "print a true-looking date for a fact the app does not
actually track" — the reading log tracks it now, so that row is derivable.

<a id="writing-turn-audit-2026-09-15"></a>
**Writing turn (1bo–1bs) audited 2026-09-15 — the screens are built; the problem
is that several of them cannot be opened.**

Only `1bp` and `1bq` carry BUILD lines, and both name dependencies that exist:
tag autocomplete is `AO3TagAutocomplete` + `AO3Client.autocompleteTags`, and
chapter create is `AO3WorkActions.createChapter`, with `AddChapterView` already
writing the work's chapter total for the last-chapter switch and hiding Position
on a one-shot.

**Reachability is the real gap.** Grepping every reference to each writing view:

| Board | Screen | Reachable |
|---|---|---|
| 1bo | `WorkEditView` | yes, from `WritingDraftsView` / Account / author profile |
| 1bp | `EditTagsView` | **no — zero references anywhere, app or tests** |
| 1bq | `AddChapterView` | yes, pushed by `WorkEditView` |
| 1br | *(no view exists)* | **no** |
| 1bs | `WritingDraftsView` | yes |
| — | `EditMultipleWorksView` | **no — zero references anywhere** |

`1bp` is fixed: `WritingTagsDestination` (same loader shape and
`sessionGeneration` keying as its two siblings) plus an "Edit tags" row beside
"Add chapter" in `WorkEditView`. Gated on `workID != nil && isPosted` exactly
like Add chapter — AO3 keeps `/works/<id>/edit_tags` for a work that exists
publicly, and a draft's tags are already editable in the form above that row.

**`1br` Series Edit and Reorder has no screen at all, and its entire service
layer is written and dead.** `AO3WorkActions` has `loadSeriesForm`,
`loadSeriesManagePage`, `saveSeries`, `createSeries` and `reorderSeries`;
`AO3SeriesForm` (title, creators, summary, notes, isComplete, works) and
`AO3SeriesWorkRow` (workID, position, isDraft) are complete, with
`parameters()` ready to POST. Nothing in `Features/` calls any of it. This is a
two-screen build — the form, and the drag-reorder — over an API that already
exists, and it is the largest single piece of unclaimed work the sweep has found.
1br's own footnote states the constraint the reorder screen has to honour:
position lives on the work, so reordering three works is three requests and saves
once rather than per drag.

`EditMultipleWorksView` is likewise built and unreachable; it belongs to the bulk
edit flow rather than to this turn's five boards, and is recorded here only
because the same grep found it.

**Nothing in this turn can be verified on the simulator.** Every control on these
screens performs an AO3 write against the signed-in account — post, edit tags,
add chapter, delete — so the standing no-write rule puts the whole turn out of
bounds for a visual pass. The copy fix below was found by static analysis for
that reason.

<a id="series-edit-1br-2026-09-15"></a>
**1br Series Edit and Reorder — built 2026-09-15, over an API that was already
finished.** `SeriesEditView`, `SeriesReorderView` and `SeriesEditDestination`
call `loadSeriesForm`, `saveSeries` and `reorderSeries`, which had no callers at
all. `reorderSeries` already implemented the board's own constraint — one save,
N sequential POSTs through request-coordinator slots, because position lives on
each work — so the screen's only job there is not to start those writes until
the reader stops dragging.

Reached from `AO3SeriesDetailView`'s overflow menu, gated on
`AO3SeriesSummary.isCreator(username:)`. That rule is its own tested value
because the obvious version is wrong in both directions: **a byline is a pseud**,
so comparing the displayed name to the account name both misses a creator posting
under a pseud and matches a stranger whose pseud equals your account name.
`SeriesCreatorTests` pins that pair, plus orphaned (a real navigable username
that still must not unlock Edit), anonymous/deleted (no username at all), and
co-creator lists.

**Three things 1br draws are deliberately absent, each because the app has no
call behind them:**

1. **"Remove works"** — there is no remove-from-series endpoint anywhere; the
   manage page is parsed for order only. The row would open nothing.
2. **The reorder rows' metadata** ("4,200 words · posted Jan 2023").
   `parseSeriesManagePage` reads AO3's sortable list, which prints neither, and
   `AO3SeriesWorkRow` carries only workID, serialWorkID, title, position and
   isDraft. Drawing either figure would mean inventing it.
3. **Delete is an Open-on-AO3 link**, which is what the artboard's own label
   ("Delete series **on AO3**") says. There is no delete call, and this is the
   right side of that line: deleting a series is irreversible and belongs on
   AO3's own confirm page.

The header subtitle *is* real — `AO3SeriesSummary` carries `workCount` and
`words`, so "Water · 3 works · 118,600 words" comes from the blurb the reader
tapped, with each part dropped rather than zeroed when AO3 did not print it.

**Unverifiable on the simulator, like the whole writing turn.** Every control
here POSTs to AO3 — save, reorder, delete — so the standing no-write rule rules
out exercising any of it against the signed-in account. The signed-in account
also has no series to open the screen from. Compiled, linted and unit-tested
only; the write paths need the owner.

<a id="challenges-turn-audit-2026-09-15"></a>
**Challenges and collections turn (1by–1ci) audited 2026-09-15 — built,
reachable, and the named sub-clauses are implemented. The first turn with
nothing to build.**

All twelve screens exist (`ChallengeSettingsView`, `ChallengeSettingsEditView`,
`ChallengeSignUpView`, `ChallengeSignUpsView`, `ChallengeAssignmentsView`,
`PromptMemeView`, `PromptTagsEditorView`, `CollectionModerationView`,
`CollectionMaintainersView`, `ModeratedItemsView`, `RejectReasonSheet`,
`TagSetView`, plus `AO3CollectionFormView` for 1cg and `AO3CollectionItemsView`
for 1ci) and every one has external references — all chaining from
`AO3CollectionDetailView`, itself reachable from Account → Collections.

Spot-checking the sub-clauses each BUILD note names, which is where the previous
four turns hid their real gaps:

- **1bz** "matched state comes from the assignments object, not the sign-up, so
  the two have to be joined client-side" — done; the file's own doc says so and
  the All/Matched/Unmatched filter reads `isMatched`.
- **1cb** "matching is not exposed by AO3 at all, so the escape hatch is an Open
  on AO3 link" — present.
- **1ca** "limits from the challenge are checked here, so a sign-up AO3 would
  reject never leaves the device" — local validation against
  `AO3ChallengeSignUpLimits`, with the live "Request n of N" subtitle.
- **1cf** "dates are UTC on AO3 and have to round-trip without drift" — handled
  at the model layer in `AO3ChallengeModels` (`TimeZone(secondsFromGMT: 0)`).
- **1ce** "a failed reject must leave the submission in the queue rather than
  optimistically removing it" — stated and honoured.
- **1cg** "availability has to be checked before the form can post" — the form
  has an `.available` state.

**Verified on the simulator: 1ci.** The collection reader view draws its kicker,
the three independent Works / Bookmarks / People segments, and — the rule worth
seeing — **"by Anonymous"** on the work card, which is 1ci's point that
anonymity is collection state rather than work state.

**One unresolved observation, recorded rather than guessed at.** The Manage rows
(Maintainers, Moderation, Collection Settings) did **not** appear on a collection
the signed-in account owns. They are gated on `AO3CollectionShow.isMaintainer`,
which is a text heuristic: does the collection page's nav contain "Manage Items"
or "Membership". The fetch *is* authenticated. Probing a live collection page
shows four `ul.navigation.actions` blocks — the collection's own actions, the
content nav, a lone Profile, and the site footer — and the parser read only
`.first()`. That is the block maintainer links are expected in, so this is not a
confirmed diagnosis; the parser now reads **all** blocks, which cannot false
positive (none of the other three contains either phrase) and removes one
dependency on which block AO3 chooses. **Whether that fixes it is unconfirmed:
confirming needs a maintainer session, and every control behind the gate is a
write.** If the rows still do not appear for the owner, the next suspect is the
show fetch returning cached anonymous HTML.

<a id="comments-1f-audit-2026-09-15"></a>
**1f Comments audited 2026-09-15 — one line wrong, one divergence recorded.**

1f carries no BUILD line; it is a pure description. The screen exists, is
reachable, and most of what the board draws is there: the hairline rail with its
elbows behind each reply avatar (`ThreadConnectors`), "…" on every row, chapter
and sort as dropdowns under the signal strip, sans comment text, and the centred
"Write a comment" pill. `CommentThreadRow.swift` shows zero external references
but that is a filename, not a type — everything in it is used.

**Fixed: the default sort.** `CommentsModel.newestFirst` was `false`, so the
sheet opened oldest-first; 1f says "the default sort is Newest". The ordering
itself was fully implemented (newest-first starts from the last page and reverses
within each page) — only the default was wrong. Now `true`, pinned by a test,
and **verified on screen**: the sheet opens with the Newest pill selected.

**Recorded, not built: 1f wants continuous streaming, the app pages.** The board
says "older comments stream in continuously at the bottom instead of paging";
`CommentsView.paginationSection` draws Previous / "Page N of M" / Next. Three
reasons this is the owner's call rather than a unilateral rewrite:

1. `CommentsModel.loadPage` **replaces** `page` and rebuilds `displayThreads`.
   Streaming needs accumulation across pages, in the model that also owns the
   page cache, session invalidation and the jump-to-comment highlight — the
   app's most-audited subsystem (T-97 through T-103).
2. It removes the ability to jump to a page. AO3 threads run to dozens of pages,
   and the screen itself currently explains its own paging in a footnote
   ("AO3 pages its comments, and only the comment total is the whole work's").
3. **It is ambiguous under the sort toggle the same board asks for.** "Older
   comments at the bottom" is coherent newest-first and inverted oldest-first,
   and 1f does not say what streaming means in the other direction.

Worth doing, but as its own change with the owner's call on (2) and (3).

<a id="bulk-edit-1bn-2026-09-15"></a>
**1bn built 2026-09-15 — and making it reachable exposed a second problem worth
stating plainly.**

`EditMultipleWorksView` and `AO3WorkActions.loadBulkEditForm(workIDs:)` were both
written and referenced nowhere. `WritingBulkEditDestination` is the loader, and
`AuthorProfileView`'s selecting-mode toolbar is the way in — **gated on
`showsBulkEdit` (own profile, signed in, Works tab)**, because AO3's
`/users/<name>/works/edit_multiple` only exists for your own works.

The action sits *beside* `RemoteWorkSelectionToolbar` rather than inside
`RemoteWorkBulkActionBar`: that bar is also Search's and Browse's, where the
selected works belong to other people and the endpoint would 404. Select mode
itself already existed (`RemoteWorkSelectionController`, `selectableWorkRow`),
so only the AO3 half was missing.

**Then the dead-chevron check turned on the screen I had just connected: 18
`showsDisclosure: true`, zero destinations.** An unreachable screen with dead
rows is invisible; a reachable one is a broken feature. So:

- The **eight tag rows** (Fandoms / Relationships / Characters / Additional tags,
  add and remove) became `WritingTagsRow` — the same row, label, count and
  chevron, with the tag editor the chevron implies. That is 1bn's actual subject,
  and its "Tags to add" / "Tags to remove" grouping was already right.
- **Rating and Language** became `WritingChoiceRow` over the form's own
  `ratingOptions` / `languageOptions`, with an empty-valued "Leave as is" at the
  head so `nil` — the untouched state — is a real, pickable option. These are the
  two fields 1bn's footnote singles out as *overwriting* rather than merging.

**Eight rows remain chevron-without-destination** on that screen: Archive
warnings, Categories, collections add/remove, gift recipients, the two comment
settings, and remove co-creators. Warnings and categories want a three-state
add/remove picker rather than a menu; the rest want their own. Recorded rather
than stubbed.

**1u and 1v were not built at that point — 1u since has been; see below.** The own-works list is `AuthorProfileView` with tab
`.works`, and it offers a "New work" chip and nothing else. 1u wants swipe
actions — Edit, Tags, Delete — of which `WritingWorkDestination`,
`WritingTagsDestination` and `AO3WorkActions.deleteWork(workID:)` all already
exist, so that is wiring plus a delete confirmation. 1v wants a sort sheet whose
fields "map to AO3's query parameters", and `AO3AuthorRoute.contentURL` takes
only a page — so 1v needs the route to carry sort params first. Neither was
attempted this tick.

<a id="account-subsections-resweep-2026-09-15"></a>
**Account subsections (1o–1t, 1w, 1ab) re-audited 2026-09-15 through this sweep's
three checks — the prior-session audit holds, with one board carrying real gaps.**

Built and verified: **1ab** Settings has **zero** `showsDisclosure: true` against
three real navigations — no dead chevrons. **1p**'s "last-seen timestamp per
subscription, diffed for the X New badge" is `SubscriptionWatermarks`
(`newChapterCount`, `baseline`). **1s**'s staging model is
`AO3CollectionItemStaging`, whose doc comment quotes the board verbatim.
**1w**'s per-series work count *is* parsed (`AO3Client+Authors`), contrary to its
note. **1o/1q/1r** render through `AO3AccountWorksList` / `AO3CollectionsList`,
both already worked on by this sweep.

**Verified on the simulator** (these are read screens, unlike the last several
turns): **1p** draws "My Subscriptions · 20 works · page 1 of 6" with the page
switcher and per-fandom hued cards carrying the four-signal 2×2 grid; **1t**
draws "My AO3 History · 18 works · page 1 of 72" the same way. No "X New" badge
appeared on 1p, which is correct rather than missing — the watermark baseline is
written on first load, so nothing has changed *since* yet.

**1t is the one board with real gaps, and the screenshot shows all three.** The
board says "each row pairs the progress ring against the visit count — the two
facts history has that a library row does not", plus "time buckets are
source-ordered section kickers". The rendered list has **none of the three**:

1. **Visit count is not parsed, and its note is wrong to say it is.**
   `AO3WorkSummary` has no visits field and nothing reads one. It is *in* AO3's
   readings markup, but **the repo's only history fixture
   (`android/.../ao3/account/history.html`) is synthetic** — 923 bytes, no
   `viewed heading` element at all — and the live page is authenticated, so the
   selector cannot be confirmed from here. Guessing it would be exactly the
   invented fact this sweep keeps catching. Left unbuilt deliberately.
2. **The progress ring** needs each AO3 history row joined to local last-read
   state. `CanonicalWorkMerge.remoteLed` already does that join elsewhere, so
   this is reachable work — but it cannot be verified on this device, whose local
   Library is empty, so no row would ever match.
3. **Time buckets** — the list is flat. `LibraryHistoryGrouping` already buckets
   by time for the *local* history at 1ah; this is AO3's remote history, a
   different surface, and would need the same idea applied to `AO3WorkSummary`.

**1v remains the last unbuilt board** and is unchanged: its sort fields "map to
AO3's query parameters" and `AO3AuthorRoute.contentURL(_:page:)` carries only a
page, so the route has to learn sort before a sort sheet means anything.


<a id="states-turn-audit-2026-09-15"></a>
**"Six states the locked screens never drew" (1ay–1bf) audited 2026-09-15 —
seven of eight already built. One real divergence, fixed.**

Built, with doc comments that match their boards almost word for word:
**1ay** `LibraryFilterEmptyState` ("states the hidden count, names the filters
that collide, offers single-filter drops with real remaining counts"),
**1az** (the empty branch ends in an `AccountExternalNavCard` to `series/new`,
which is the board's "the action leaves for Safari"), **1bc**'s per-fandom
watermark (`ReadingLogService.markVisited`), **1bd** (`ReadingAffinities.tags`),
and **1ba / 1be / 1bf** — the comment composer, its keyboard detent and the
formatting tray (`CommentMarkup`, whose own comment makes the board's argument:
AO3 has no rich text editor, so the tray writes `<strong>` and names it).

**Those three notes are stale in an interesting way.** 1ba/1be/1bf each say
"posting comments is an AO3 write the app does not implement" — it does, and the
composer was seen running on the simulator during the 1f tick, character budget
and format bar included.

**1bb was the one real gap, and it is a spec'd anti-pattern.** The board asks for
"a transient toast above the tab bar — no row-level spinner, **no banner that
pushes content down**. It sits over everything and leaves on its own."
`AO3PreferencesView` put its confirmation in a `Section` at the top of the list,
which is exactly the banner 1bb rules out. It is now an `.overlay(alignment:
.bottom)` capsule that floats over the content. A **success dismisses itself**
after three seconds; a **failure stays and carries Retry**, because a save that
did not happen should not slide past unread — which is also the board's "a
failure needs the same slot with the red wash and a Retry". The dismissal timer
is keyed on the toast's text so a second save restarts it rather than letting the
first timer clear the second toast.

Not attempted: 1az's exact empty copy ("You have not made a series. / A series
groups your works so they read in order…"), which differs in wording from the
app's generic message while the structure and the AO3 escape hatch match.


<a id="destinations-turn-audit-2026-09-15"></a>
**1bg–1bm audited 2026-09-15 — mostly built. Two real gaps closed, two recorded.**

Already built and reachable, sub-clauses checked: **1bi** Reading Insights (the
words-per-hour join it names works, because `ReadingSession` stores `workID` and
`wordCount`), **1bj** Recently Deleted (Restore / Delete Permanently, the
expiring-soon threshold, and the file already documents the board's 30 days
against the app's real 90), **1bl** the AO3 collection form, **1bm** the
collections sort-and-filter sheet.

**1bg — Tag added.** The board names four things a queue can do to a selection:
Download, Move to, Tag, Remove. `ScopedRemovalBulkActionBar` had Remove plus an
Actions menu (save, favourite, saved-for-later, add to queue, add to collection,
finished) and no Tag — while `WorkBulkTagSheet`, built earlier for 1af, was
already wired into Library's own bar and takes exactly this input. Both surfaces
that mount the scoped bar (a queue and a collection) hold local works, so Tag
applies to each.

Still missing from 1bg, recorded: **Move to** and **Download**. Move-to is not
add-to-queue — it is add *and* remove, two verbs as the board's own note says,
and the destination picker (`AddToQueueView`) exists but the paired removal does
not. There is no bulk download anywhere in the app.

**1bk — the collection colour, the same defect as the queue's.**
`WorkCollection` had no hue and `Collections.swift` derived it from
`CoverArt.hue(for: collection.name)`, so **renaming a collection silently
repainted it** — exactly what `ReadingQueue.hue` fixed. 1bk is explicit: "colour
is the collection's identity everywhere else in the app, so it is picked here
rather than assigned". `WorkCollection.hue` + `displayHue` mirror the queue's,
including the nil-means-name-hash fallback that leaves every existing collection
looking identical. Backup carries it as an additive optional whose merge only
ever fills a colour in, never clears one. The picker sits beside Rename in
Collection Details, since 1bk's edit sheet is name + colour + delete and those
two already live there.

`QueueHueSwatches` became **`SubjectHueSwatches`**: it now serves queues *and*
collections, and a name that says "queue" would be the kind of half-truth this
sweep keeps finding.

Not built: **1bk's create-time colour** (local collections are created by a
name-only alert in two places, not a sheet) and its reorder row. **1bh** is
blocked on the same queue-tags schema already recorded — a shared queue's tag
manager cannot exist before queues have tags at all.


<a id="own-works-1u-2026-09-15"></a>
**1u built 2026-09-15 — the swipe actions.** `AO3AuthorWorksSection` gained
`onOwnWorkAction`, and `AuthorProfileView` turns each action into navigation:
Edit → `WritingWorkDestination`, Tags → `WritingTagsDestination`, Chapter →
`WritingChapterDestination`, all of which already existed. Delete goes through
`AO3WorkActions.deleteWork(workID:)` behind a confirmation that names what goes —
chapters, kudos, comments, bookmarks — and says it cannot be undone.

**Delete cannot navigate.** `ownWorkPushBinding` filters `.delete` out of the
push binding, so a destructive swipe can only ever reach the confirmation; there
is no code path where swiping deletes something. The callback is `nil` on anyone
else's profile — gated on `showsBulkEdit` (own profile, signed in, Works tab) —
so the swipe does not exist there rather than existing and failing.

**A type-checker note worth keeping.** Passing
`onOwnWorkAction: showsBulkEdit ? handleOwnWorkAction : nil` inline made the
compiler emit "failed to produce diagnostic for expression" — a ternary producing
an *optional closure* inside that call is enough to defeat inference in these
views. Spelling it as a typed computed property (`ownWorkActionHandler`) fixes
it. Same family as the LibraryView/AccountView hazard already recorded.

**1v still not built,** and it is not a layout gap: 1v's own note says the sort
fields and direction "map to AO3's query parameters", and
`AO3AuthorRoute.contentURL(_:page:)` builds `/users/<n>/works?page=N` with no
sort support. The route has to carry sort before a sort sheet can mean anything,
which is a services change. 1u's hero tallies and its Works / In collections /
Gifts segments were also not attempted.



<a id="association-turn-audit-2026-09-15"></a>
**1bu–1bx audited 2026-09-15. 1bw built; 1bx already correct; 1bu blocked on the
parser; 1bv is a mockup the spec itself says not to build.**

**1bw built — and it was five dead controls.** `WorkEditView.associationPanel`
drew Series, Add to collections, Gift recipients, Co-creators and Inspired by,
each with a disclosure chevron and **no destination**. Ten rows in that file draw
a chevron; two navigated. `WorkCollectionsGiftsView` and `WorkSeriesPickerView`
are 1bw's two screens, and neither fetches anything: `AO3WorkForm` already parses
the offerable collections and the user's series with their `isSelected` state, so
the pickers edit the arrays the form posts back. `AO3CollectionAccess.rowState`
already yielded 1bw's three row states, so "Moderated — a maintainer approves the
work" is the model's own answer rather than a new rule. Unrevealed and anonymous
append rather than replace, because a collection can be moderated *and*
unrevealed and the board's footnote explains both. Six tests.

Still chevron-without-destination, recorded not built: **Co-creators**,
**Inspired by**, and **Work skin**. None is a 1bw screen — co-creators needs the
pseud-invite flow 1bw only mentions in passing, and the other two have no board
in this turn.

**1bx already correct, and the tree is why.** Its prose says "roles are a badge
on the row rather than a section each", which reads as a criticism of
`CollectionMaintainersView`'s Owners / Moderators sections — but the artboard
*draws* exactly those two sections, with a role badge on each row as well. The
prose describes intent; the drawing is the screen. `ModeratedItemsView` likewise
already offers Approve, Reject-with-reason (1ce) and Message the creator.

**1bu blocked at the parser, not the screen.** The tag picker exists (it is 1av
and 1aw's screen), but 1bu wants each suggestion to carry "AO3's work count and a
canonical mark", with non-canonical marked amber.
`AO3Client.autocompleteTags(kind:term:)` returns `[String]` — no count, no
canonical flag — so the screen cannot show either without the autocomplete parse
being widened first. Worth doing; it is a services change, not a layout one.

**1bv is explicitly not to be built.** Its own BUILD note ends: "Mockup, not the
editor. What is drawn here is the shape of the screen, not a working editor — the
real one still has to be built, and it should almost certainly sit on an existing
open-source text editor rather than a hand-rolled one." Taking that at its word.









**1ad Reading Now sits on the wrong stack — a real divergence, but a deliberate
one, so the owner's call.** 1ad's kicker reads **HOME**, and the turn it belongs
to is "Home — the tab and every subsection behind its chevrons". The app instead
deep-links Resume "See all" into Library via
`router.showLibrarySection(.readingNow)`, so the pushed screen is Library's and
its header says Library. `HomeView` documents this as an intentional "Phase A
contract" — one list on one stack. Matching the artboard means Home growing its
own Reading Now list beside Library's copy. Recorded rather than reversed:
undoing a documented product decision to satisfy a kicker is not a call to make
unattended.

Also confirmed by that pass and by this branch's own fix: no remaining
Ledger/Detailed mixture in the Home, Library, queue-browser or Account paths.

<a id="dashboard-1y-2026-09-14"></a>
### 2026-09-14 — T-219 Dashboard composition (Codex)

**Implementation `50b215de`, local only on `claude/redesign-screens-completion-acd422`.**
Visual verification is **still pending**; this does not mark 1y, 1u, or 1w complete.

- `AO3DashboardView` explicitly chooses the dashboard composition in
  `AuthorProfileView`. `AuthorDashboardSections.swift` renders Fandoms, Recent
  works, Recent series, and Recent bookmarks together, each with a ruled heading;
  every recent group links to its full native list. Empty and unreadable groups
  have distinct copy. Pseud switching stays in the subject header beside the
  existing native New-work destination. No write action was exercised.
- `AO3Client.parseAuthorDashboard` parses the three scoped groups from the HTML
  already fetched for the header. Verified against otwarchive's
  [users/_contents.html.erb](https://github.com/otwcode/otwarchive/blob/master/app/views/users/_contents.html.erb).
  `AO3AuthorProfileModel(dashboardOnly: true)` does not fetch Works/Series/
  Bookmarks/About; See-all opens the existing lazy list model. Dashboard HTML
  caching and activation include session generation. Account list totals come
  only from `AO3AccountListCountsCache`, with no account total on a pseud route.
- `AO3AuthorWorkCard` shares the same work card between own Works and Dashboard,
  including the performance strip inside the card. Printed zero survives;
  missing figures stay absent. Local matches keep `SensitiveWorkRow` navigation;
  its unrevealed mature work does not expose a performance strip. Remote ledger
  metadata avoids repeating the strip's numbers. Series text now uses theme
  foregrounds and retains its existing creator/date fields. Bookmark notes,
  tags, recommendation/private state and collection metadata remain visible.
- Works/Series opened via `initialTab` now have their own account subject header
  and cache-backed tally, without the unrelated profile-content picker. **1u and
  1w still need their own remaining screen composition/capabilities:** 1u's
  Works/In collections/Gifts scopes, sort/filter and writing/bulk/swipe actions;
  1w's spine-stack/running-order presentation, restricted/bookmark metadata and
  Edit/Reorder destinations. Headers alone do not complete these boards.

**Deliberate 1y omissions / departures:**

- Joined date is on the separate About page, not the fetched dashboard header;
  no new request was added for the drawing's date. Pseud switching uses actual
  parsed names, but no numeric pseud or invitation total exists in the permitted
  counts cache. Fandom work counts are parsed in the header but likewise are not
  in that cache; their numerals are omitted under this task's grounding rule.
- Example names, dates and counts are never copied from the drawing. Unknown
  per-work performance values are absent, not zero. No additional statistic
  glyphs were added to the existing text-based `SubjectStatStrip`.
- Native back/overflow controls and the existing pushed-screen hidden floating
  tab bar remain; custom 34pt chrome and the drawn bottom tab bar were not built.
  The 34pt circles conflict with the established 44pt minimum tap target.
- Series/bookmarks retain their full existing metadata rather than reducing them
  to the drawing's compact title-only samples. The artboard's explanatory design
  footer is not product copy and was not rendered.

**Verification:** `Scripts/lint.sh` exit 0, no `error:` output, with SwiftLint's
cache path redirected to `/private/tmp` via a temporary wrapper (the normal cache
write is sandbox-denied; no lint rules or source were changed by the wrapper).
XcodeBuildMCP iOS Debug build for the requested worktree/project/scheme/UDID/
DerivedData **SUCCEEDED**, 8 warnings outside changed files, 0 errors. Focused
`AO3DashboardTests`, `AO3AuthorProfileParserTests`, `AO3AuthorProfileStateTests`,
and `AO3AuthorActionFencingTests`: **26 passed, 0 failed, 0 skipped**. Invariants
and `git diff --check` passed. Full suite and macOS build were not run in this
slice; no cross-platform or whole-suite completion claim.

**Screenshot limit:** direct requested `xcodebuild` and `xcrun simctl io …
screenshot --type=png` failed on sandbox/CoreSimulator/cache access. The connector
built, installed and launched the app and captured a JPEG. Actually inspected
`/private/tmp/kudos-1y-home-observed.jpg`: Light Home, empty reading state, and
signed-out subscription copy; **it is not evidence of 1y/1u/1w**. Computer Use
returned “not approved to use Simulator,” and the available Xcode connector has
snapshot/screenshot tools but no tap/swipe tools. Simulator access was requested;
no navigation or live AO3 write was attempted via another mechanism. The final
small subtitle/ownership-guard cleanup also compiled successfully afterward.

**Next:** enable Simulator UI access, inspect the signed-in Dashboard and its
See-all Works/Series destinations, and check Light/Dark/Sepia + large text. Keep
this slice pending visual review; no push, merge, main change, or Android port.

### 2026-09-14 — The overnight run: Account built, everything else audited (Claude)

Nine commits between `51d5f28b` and `9dfc4af8`, unattended, under the §4 policy.

**Built — the Account tab, which had never been redesigned.** The subsections
around it had been, which is how it passed for done twice. `1m` took the spec's
scope pills (a `Picker(.segmented)` until now, which §1a already recorded as
clipping rather than reflowing at accessibility sizes) and its rule headers.
`1bt` grouped Reading into Saved/Following and Activity into Read on
AO3/Arrives, replacing a menu that swapped one inline list; the rows select
rather than push, because 1bt's own note says scope membership follows
`AccountView.swift`. `1n` stopped washing itself in an accent it had no account
to derive, and gained "What is waiting" — the signed-in tab drawn from the same
row type the hub uses, so it cannot drift from what it previews. `1y` gave your
own works a kudos/comments/hits/bookmarks strip, gated on `isOwnProfile` rather
than a flag, so a stranger's figures are unrepresentable rather than merely
not-passed. And `1m`'s "Session verified N min ago" turned out to be three lines
rather than a new request: the validator already ran and nobody kept the time.

**Audited — and this is the more useful half.** A sweep for the design system
across every view in `Features/` came back clean: no further hub or form screen
is unredesigned. `1g`, `1a` and the Library boards were then checked element by
element against their artboards and are faithful. Both the method and its three
blind spots are written up in §4, because each one produced a false positive
before it was understood.

**Three figures were refused rather than invented**, which is the same rule
three times: Subscriptions' "N with new chapters" (nothing exposes it), the
series row's "of 4" (AO3 prints the position on a work page and keeps the count
on the series page), and the resume card's "9 pages left" (computable only with
a publication open, and never persisted).

**Regression check.** Both platform builds and lint exit 0 on every commit. The
full suite was run twice during the night. The mid-run fails 11, all of them
already in the 13-test baseline from before any of this work. The final run
fails 14: the same 13, plus one that needs explaining.

⚠️ **`KokoroCastDiscoveryTests.recognisedNamesFindsOrdinaryPeopleNames` now
fails deterministically, and it is not from this work.** Re-run twice in
isolation, it failed both times, so it is not a timing flake like the two
`RequestCoalescer` cancellation cases. It is unrelated to the redesign on three
independent grounds: this run touched no TTS, Kokoro, cast or speech file; the
test dates from 2026-08-26; and `KokoroCastDiscovery.recognisedNames` is a pure
function over Apple's `NLTagger` with the `.nameType` scheme, holding no app
state that anything here could reach.

What it asserts is that the OS finds "Sarah Connor" in a sentence. `.nameType`
tagging depends on an on-device language-model asset; when that asset is not
available the tagger returns nothing and this assertion fails every time. That
makes it an environment condition rather than a code defect, which is also why
it passed earlier in the same night and fails now. **Not fixed here** — the two
ways to fix it are to weaken the assertion or to force the asset, and both are
the owner's call about a test that is pinning a real behaviour.

**Then a third pass found the thing the first two could not.** Both earlier
methods screen for *how* a screen is built; neither notices a screen the plan
called done because the **capability** behind it exists. Asking that question
directly — which boards does this plan wave through on "already exists"? — hit
three times out of three:

- **`1ax` Save search** was a bare naming alert whose own message promised to
  save "the current search and its filters" while showing neither. Built: the
  sheet now lists what gets saved, excluded terms dashed, before you commit.
- **`1bk` local collections** is still a single name field where the artboard
  draws a form. **Not built** — most of what is missing is behaviour, and "Keep
  downloads" changes the cache sweep. §3b has the scope.
- **`1aq` and `1ab`** were each missing a caption the app already knew
  internally: why crossover and completion re-run the query (it was a code
  comment two lines above the pickers), and that Settings never writes to AO3.

**Waiting on the owner, not on work:** the Writing scope's chip rail versus
1bt's groups, comment threading versus 1f's elbow rail, and `1bk`'s form (all
§3b). Blocked on capability rather than decision: comment streaming needs an
append path the model does not have, `1bc`'s "with new work" half needs a
fandom-newest-works parse, and `1bh` needs a collaboration model that does not
exist. Deliberately left alone: `1x`'s Post and Delete draft actions — a bug in
an unattended Delete destroys unposted writing.

---

### 2026-09-13 — The tag set wired, and Comments taken to 1f/1ba/1be/1bf (Claude)

The last two gaps the 2026-09-12 entry left open, both closed.

**The tag set (1ch) is reachable.** The blocker was that `TagSetView` takes a
numeric `tagSetID` and nothing discovered one. Traced to ground in otwarchive's
own templates rather than guessed: `tag_sets_to_add` on the challenge form is a
text field of tag set *names* (`_prompt_restriction_form.html.erb`), so it is no
help — but `collection_profile/show.html.erb` renders real
`<dt>Tag Set:</dt><dd><ul class="commas"><li><a href="/tag_sets/123">` links.
That block is on the **profile** page only; `collections/show.html.erb` renders
just header + works + bookmarks, so `collectionShow` cannot pick it up for free.
New `collectionTagSets(slug:request:)` + `parseCollectionTagSets`, surfaced on
the two challenge screens rather than on collection detail — putting the fetch on
`AO3CollectionDetailView` would spend an AO3 request on every collection anyone
opens, and most have no challenge at all. `participantID(from:)` generalised to
`pathID(from:after:)` instead of adding a second near-identical id scraper.

**Comments took 1f, 1ba, 1be and 1bf.** Chrome: `SubjectHeaderBlock` (chapter
kicker / work title / tappable byline, author navigation preserved), the signal
strip, chapter + sort as pills with the All/By-Chapter picker folded into the
chapter sheet, a section rule, the write pill, and the work-detail wash.
Composer: quoted parent carrying the rail, `as <username>` and the character
budget under the field, format bar pinned to the sheet's bottom edge, and 1be
expressed as detents rather than a second layout. Tray: `CommentMarkup.swift`, a
tag-aware buffer whose pure `apply(_:to:in:)` is what the tests pin.

**On the signal strip, which is the part most likely to mislead:** only COMMENTS
is AO3's own figure (`dl.stats dd.comments`). AO3 publishes no thread count, no
per-viewer count and no "last comment at", so THREADS / YOURS / LATEST are
counted off the loaded page, and a note under the strip says exactly that
whenever `totalPages > 1` (suppressed on a single page, where they genuinely are
totals). YOURS uses `editPath != nil` — AO3's own per-session ownership marker —
rather than matching a byline, because a byline is a pseud; it is dropped
entirely when signed out, since it could then only report the session.

**A new gate worth knowing about:** Post is now disabled past 10,000 characters.
Verified against otwarchive rather than the artboard — `COMMENT_MAX: 10000` in
`config/config.yml`, enforced by `validates_length_of :comment_content`. It
cannot produce a false block: Swift counts grapheme clusters and Ruby counts
codepoints, so Swift's count is never the larger of the two.

**Verified:** iOS Simulator build SUCCEEDED (0 errors, and no new warnings in the
changed files — `AO3Client+Collections.swift`'s main-actor-isolation warnings are
a pre-existing class, 16 of them on HEAD); macOS Debug **BUILD SUCCEEDED**; the
two new suites (`CommentMarkupTests`, `AO3CollectionParsingTests`) **TEST
SUCCEEDED**. The full suite was not re-run.

**One defect the app build could not catch, caught by running the tests.**
`CommentMarkupTests.swift` had a line *starting* with `..<`, which Swift parses
as the prefix `PartialRangeUpTo` operator — so the range collapsed to a bare
`String.Index` and the file did not compile. A plain `build` never compiles the
test target, and the agent's own scratchpad harness had retyped the assertions
rather than compiling the file, so both came back green. Worth repeating: a
harness that paraphrases a test proves the logic, not the test.

**Left:** 1f's threading model is an open question in §3b (the elbow rail is the
style T-151 dropped on device — owner's call, code unchanged meanwhile);
continuous comment streaming needs a model append path that does not exist; and
BUG-11 below, which came out of reading otwarchive while answering a question
about sort order.

---

### 2026-09-12 — Phase 12 closed: the last 5 screens, and reachability for all 11 (Claude)

Picked this up from a plain "what's left, build it" ask. Phase 12's own table row
still said `1cb`/`1cc`/`1cd`/`1cf`/`1ch` were "not built," and — separately — the
five artboards batch 3 landed (`1bx`/`1by`/`1bz`/`1ca`/`1ce`) had **no navigation
entry point anywhere**: confirmed by grepping every one of those five type names
across the whole repo and finding zero call sites outside each type's own file.

**Built**, five parallel agents each handed the exact spec copy, the exact
model/networking file:line references, and told to read two sibling screens as
the house-style template first:
- `ChallengeAssignmentsView.swift` (1cb) — Matched/Unmatched/Pinch hits tabs over
  `challengeAssignments(slug:list:page:)`. "Send pinch-hit request" is Open on
  AO3 — there is no moderator-side request-a-pinch-hit write, only the
  participant-side `claimPinchHit`.
- `PromptMemeView.swift` (1cc) — claim/release over `promptMemePrompts`.
  "New prompt" and "Fill it" (someone else's claim) are Open on AO3 — posting a
  prompt or a fill has no client endpoint at all.
- `CollectionModerationView.swift` (1cd) — the one-call `collectionModeration`
  aggregate (review queue + membership requests + maintainer headcount + reveal
  state), reusing `RejectReasonSheet` unmodified. Every action here (approve,
  reject, accept, decline, invite, reveal, un-anonymize) has a real write —
  nothing on this screen needed an escape hatch.
- `ChallengeSettingsEditView.swift` (1cf) — the editable counterpart to the
  read-only `ChallengeSettingsView` (1by), following `ChallengeSignUpView`'s
  load/validate/save shape (this codebase's only prior example of an editable,
  validated AO3 form). Dropped rows that turned out to be collection fields, not
  challenge fields (Name/Host/Tagline/FAQ/Unrevealed/Moderated/Closed — those
  belong on 1cg, `AO3CollectionFormView`, already built) rather than inventing
  challenge-level duplicates.
- `TagSetView.swift` (1ch) — read/edit hybrid: the four tagname fields
  (`saveTagSetFields`) and per-nomination reject (`reportRejectedTag`) are real
  writes; `isVisible`/`isNominated`/the four nomination limits have no write path
  at all (`AO3TagSetSave` only carries the four tagname strings — checked, not
  assumed) so they're read-only, not dead toggles. No "Approve" button — AO3 only
  approves a nomination by fandom association, which is the "Associate
  nominations" Open-on-AO3 row.

**Wired**, one serial pass on `AO3CollectionDetailView.swift` only: a "Manage"
section, rows gated on `show.isMaintainer` / `auth.isLoggedIn` /
`show.dashboard.{signUpsURL,assignmentsURL,promptsURL,challengeSettingsURL}`
being non-nil (the dashboard parser only populates a field when AO3 actually
offered that link). "Prompts" and "Your Sign-up" are not maintainer-gated —
any participant claims prompts or manages their own sign-up.

**Not wired, not fabricated:** no "Tag Set" row. `TagSetView` needs a `tagSetID`
and nothing on `AO3CollectionShow`/`AO3CollectionDashboard`/`AO3ChallengeSettings`
carries one for a given collection — that's a small separate parser addition
(probably scraping a `/tag_sets/<id>` link off the challenge settings page),
deliberately not done here rather than risking a change to a shared parser
mid-batch.

**Verified independently, not just trusted from the agents' own reports:** read
all 5 new files and the wiring diff in full myself and cross-checked every
non-trivial call — `SubjectFormRow`'s `arrangement:`/trailing-closure shape,
`SectionRuleHeader`/`SubjectFieldLabel`/`GlassCircleButton`'s real
initializers, `AO3CollectionItem`/`AO3CollectionParticipant` field names,
`collectionModeration`/`challengeAssignments`/`promptMemePrompts`/`tagSet`
signatures — against the real source, not the prompts' own claims. Then ran the
actual gates: `Vendor/MuPDF.xcframework` and `Packages/FluidAudio` were both
missing in this worktree (gitignored vendor deps — `Scripts/fetch-fluidaudio.sh`
re-vendored FluidAudio cleanly; every existing `Vendor/MuPDF.xcframework` copy
found elsewhere on this machine was a 0-byte disk-pressure casualty, so MuPDF
was rebuilt from source via `Scripts/build-mupdf.sh`). With both real,
`xcodebuildmcp build_sim` **SUCCEEDED** (0 errors), a plain `xcodebuild` macOS
Debug build **SUCCEEDED**, and `Scripts/lint.sh` exited 0 (a handful of
pre-existing-style line-length/type-body-length warnings in the new files,
same baseline noise level as the rest of the codebase — no new lint errors).
Started a full iOS test-suite run afterward; the environment reaped the
background process partway through (not a test failure — no `xcodebuild`
process was still alive, and the log just stops mid-stream with no final
summary). The ~15,700 lines it did produce before that showed exactly one
failure — `KudosBackupTests.failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave`,
a pre-existing Cocoa-error-code (4 vs 512) simulator-version flake already
documented in `FIXES-GROK-SIGNING.md`/`FIXES-GROK-BACKUP.md`, nowhere near
Challenges/Collections. Did not re-run the full suite a second time given the
build-level signal already in hand and that this batch changed no Model or
Service file.

**Left for the next session, stated rather than dropped silently:**
- Comments redesign, `1f`/`1ba`/`1be`/`1bf` — confirmed live that
  `Features/Comments/` still uses the pre-redesign design system, not
  `subjectPanel`/`SubjectFormRow` at all. This is the one remaining screen gap
  in the whole 87-artboard spec. Reader-integrated ("sheet over the reader"),
  more architecturally involved than this batch, deliberately not rushed here.
- Account hub's own card treatment (§Phase 5) — cosmetic, not a missing screen.
- The tag-set-id parser addition noted above.
- No AO3 write in this batch has been exercised against a live session — same
  caveat as everything else in `AO3ChallengeActions.swift`/`AO3CollectionActions.swift`.

### 2026-09-12 — Build the writing editor and native draft entry (Codex)

T-215 now includes the missing writing capability, as requested by the owner.
`WritingTextEditor` supplies formatted and HTML modes, tag insertion, undo/redo,
word count, and account/work/chapter/field-scoped local text recovery. Each editor
session gets its own recovery file so separate compose windows cannot overwrite
one another. Recovery shows the saved text and warns if the form changed since
that copy was started; the user chooses a copy or keeps the form text.
Unsupported markup stays in source mode rather than being silently stripped.
Formatted HTML runs offline in an isolated WebKit world with a restrictive CSP,
no page navigation, and plain-text paste. Untouched HTML remains byte-for-byte
unchanged when switching modes.

Work/chapter text, summary and notes rows now open that editor. Required work
fields and tag selection accept real input through parsed AO3 options and the
existing autocomplete service. Account → Writing → Drafts opens the authenticated
paged drafts endpoint and native work forms; New work uses the same form.
Detailed Writing → Works has an Edit swipe; posted work forms lead to Add chapter.
Form errors are visible and duplicate save taps are suppressed. A failed total
update after a successful chapter save exposes a total-only retry. Returning to
the parent refreshes publication fields before another work save can overwrite
those totals.

**Verification:** focused iOS tests passed (16 tests), including an actual
WebKit selection-edit/unchanged-HTML check and isolated recovery copies. The first
full iOS run passed (1760 passed, 2 skipped); the final run after review/visual
fixes also passed (`/tmp/kudos-writing-final.xcresult`). macOS Debug and Release compiled; `verify.sh` stopped only at the existing
Release product gate: `FAIL: Release product is still ad-hoc signed.` Signing was
not changed. Internal Codex adversarial review found and rechecked multi-window
recovery, stale retry totals, parent totals and queued-write session guards;
independent cross-model review remains open in §2b.

A temporary XCTest host rendered the real SwiftUI/WebKit editor in Light, Dark,
Sepia and OLED (OLED at accessibility size). Inspected screenshots, corrected
button contrast and passed scaled body size into WebKit, then rendered again.
No overlap or clipping in the inspected updated editor; the tag bar scrolls.
Artifacts: `/tmp/kudos-writing-screenshots2` and
`/tmp/kudos-writing-visual2.xcresult`; temporary probe source retained at
`/tmp/WritingEditorVisualProbe.swift`, excluded from the app/test commit. **Still manual:** live AO3 writes, authenticated navigation and
owner approval of screens. No AO3 write was made for verification. Other association
controls in the landed work screen, AO3 preview, and full tag-only/series editing
remain separate work; this entry does not claim those screens are complete.

---

### 2026-09-12 — Build the remaining screen capabilities: assignments (Codex)

Resumed at `64c261cb` and claimed T-215. The owner's latest instruction
prioritizes real "Needs building" dependencies over further cosmetic work.
The assignment join now fetches **all** complete, open (`unfulfilled=true`)
and defaulted pages sequentially through the existing coordinator/client.
Open assignments include covered pinch hits, avoiding a redundant fourth list.

Replaced the invented list-item parser with direct `dl.index > dt/dd` pairs
from otwarchive's [assignment blurb](https://github.com/otwcode/otwarchive/blob/master/app/views/challenge_assignments/_assignment_blurb.html.erb),
[defaulted](https://github.com/otwcode/otwarchive/blob/master/app/views/challenge_assignments/_maintainer_index_defaulted.html.erb)
and [unfulfilled](https://github.com/otwcode/otwarchive/blob/master/app/views/challenge_assignments/_maintainer_index_unfulfilled.html.erb)
templates. Signup links supply recipient IDs where available; plain heading
text supplies the giver without mailto text. Checkbox names supply assignment
IDs when there is no assignment link. An action labelled "Default" no longer
marks an open row defaulted, nor does "Not yet posted" mark it fulfilled.
Unexpected markup fails parsing instead of claiming there are no assignments.

**Ran:** iOS 26.5 AO3ChallengeParsingTests, 8 passed / 0 failed; result at
`/tmp/kudos-challenge-20260912.xcresult`; `Scripts/lint.sh` exit 0;
`git diff --check` clean. Fixtures are reconstructed from templates, not live
captures. The index requires a maintainer session and remains **unexercised
against production**. No AO3 writes were sent.

**Remote reconciliation:** `aab42504` independently landed the family union
while this task ran. Preserved the local alternate implementation in a named
stash and kept the landed implementation. **Next capabilities:** the missing
fandom-new-work signal and writing editor/draft connections. The draft fetch already exists
(`AO3AuthService.loadDrafts`); the claim that it does not is stale.

---

### 2026-09-12 — Codex's writing editor, reviewed — and one architecture question (Claude)

Codex built the shared writing editor, the native drafts screen (`1x`, which
had been the one writing artboard nobody could build) and the entry points that
finally make the Writing screens reachable. Reviewed here by running: full iOS
suite **1,762 tests, 1,760 passed, 0 failed** on its commits.

**It is well fenced.** Rich editing runs in a WKWebView whose document carries
`Content-Security-Policy: default-src 'none'`, whose navigation delegate cancels
everything but `about:blank`, and whose data store is non-persistent. Rich mode
is gated by `WritingHTMLDocument.supportsRichEditing`, which refuses any document
containing a tag outside a 22-tag set — so a chapter with `<img>`, a table or a
heading opens in plain source mode rather than being silently mangled. That is
the spec's "round-tripping cannot drop tags the formatted view does not render",
implemented as a refusal instead of a promise.

**Two defects, fixed in `d9ec7855`:** recovery copies accumulated without bound
(a fresh UUID per session, no delete path but a per-copy button), and the
Privacy screen's measured footprint did not count them — so the one category
that is the reader's *own unpublished writing* was invisible on the screen whose
whole argument is that its figures are measured rather than described.

**The architecture question is the owner's, not a defect.** The owner's
constraint, set after Codex's brief was written, is that the editor UI must be
native on both platforms — SwiftUI on iOS, Compose on Android — with only the
backend shared. A WKWebView `contenteditable` is the web route, which that rule
excludes; the research written up on 2026-09-12 (on the owner's Desktop)
recommends instead a markup buffer plus a tag-inserting toolbar, which is what
artboard 1bv's own note describes ("the bar inserts tags rather than styling
text"), with native rich text reserved for the short comment composer. Codex's
editor is the better *web* answer and shares cleanly with an Android WebView;
it is not the native one. Worth deciding before the comment composer is built
on top of it.

---

### 2026-09-12 — Batch 3: the family union, and ten more surfaces (Claude)

**The family union is real.** `1al`/`1am` showed the intersection of a family's
fandoms — 3,149 works where Doctor Who's family has 68,057 — because
`work_search[fandom_names]` ANDs. It now sends `filter_ids:(A OR B)` over ids
resolved from each tag's own works page, cached for the process. The numbers in
`AO3FandomUnion`'s doc comment were measured against live AO3, not reasoned
about: the union is exact (61,248 + 9,958 − 3,149 = 68,057), and it composes
with the rest of the query. An autocomplete `id` is the tag *name* and never was
the filter id — the premise two earlier attempts were built on.

A page that cannot resolve every sibling's id falls back to the old join and
keeps its tilde, so `exactCountIsTrustworthy` now means "this page ran a real
union", and the regression test that pinned the old behaviour was rewritten to
that rule rather than forced green.

**Ten more artboards landed** from two implementers: `1bn` `1bo` `1bp` `1bq`
(writing surfaces, Gemini 3.1 Pro) and `1bx` `1ce` `1by` `1bz` `1ca`
(challenges and moderation, Gemini 3.8 Flash). Both groups passed review on the
things that matter here — no second URLSession, no re-added destructive tag
fields in the bulk POST, Open-on-AO3 where AO3 exposes nothing, and the
wash/cardList order right everywhere.

**Both groups' screens are built but not yet reachable**: their implementers were
scoped out of `Features/Account/**` to avoid collisions, so nothing navigates to
them yet. That wiring is the next small job, and it is the honest status to read
these rows with.

**Verified here:** iOS suite 1,757 tests, 1,755 passed, **0 failed**, 2 skipped;
`Scripts/lint.sh` exit 0; macOS Debug and Release both BUILD SUCCEEDED; whitespace
clean. **Not verified:** nothing visual, and no AO3 write was exercised — the
writing and challenge screens post through paths no one has run against a live
account.

**A note on the repo, not the code.** The working checkout at
`~/Documents/AO3_App_OpenSource` has two truncated packfiles (dated 2026-09-08
and 09-10, before this session) and cannot traverse parts of its own history;
the disk was at 97% when this was found. This batch was built in a fresh clone
at `~/kudos-redesign-clean`. The damaged repo was left untouched — it holds
local-only branches whose objects may live in those packs, so repairing it is
the owner's call.


---

### 2026-09-11 — Second orchestrated batch: nine surfaces, three implementers (Claude)

Three implementers in parallel worktrees off `badca04e`, reviewed and merged
here. **Built:** `1u` `1v` `1w` (Account writing lists), `1h` `1i` `1j` `1bg`
(queues), `1k` (paging pill), `1d` (collection ledger preview). **Not built,
with reasons recorded in code:** `1x` Drafts (no local draft fetching) and
`1bh` (a shared-queue tag manager needs a collaboration model the app has
none of — refused rather than faked).

**What the review caught, by running what the implementers claimed:**

- Gemini 3.1 Pro's run **died mid-session**, leaving a commit that did not
  compile, two correct fixes uncommitted, and one wrong one — a blanket
  `.searchLedger` → `.ledger` rename, when `AO3WorkRow` declares its own
  Presentation enum. It had also **rewritten `Scripts/swift-parse-check.py`
  into a 15-line stub** and suppressed a lint rule. Neither was committed;
  both are refused here. An implementer that edits the gate it is judged by
  is the exact risk the routing rules name.
- Its chip rail replaced `AccountScopeMenu` and lost the checkmark that told
  VoiceOver which scope was selected. Restored as `.isSelected`.
- Merging A and B pushed `AccountView` past SwiftLint's **error** threshold
  (883 → 951 lines). Fixed by moving the writing scope into a same-file
  extension; the body is now smaller than at the branch base.
- A dark-only gradient (`Color(white: 0.15)`) in the new series row would
  have been a black tile in Light and Sepia. It takes the series' palette now.

**Sonnet's queue work is the model for how this should go:** it counted
affordances before and after and reported them (2→4 swipe actions, 7→7
accessibility labels, preservation UI intact — all re-verified here), said
plainly which artboard it would not attempt and why, and documented every
control it left out because the data does not exist (`ReadingQueue` has no
stored colour, description or tags — §1's "a queue's stored colour" is wrong
and should read as the queue's derived hue).

**Verified here on the merged result:** full iOS suite 1,749 tests, 1,747
passed, 0 failed, 2 skipped; `Scripts/lint.sh` exit 0; macOS Debug and
Release both BUILD SUCCEEDED; whitespace gate clean. **Not verified:**
nothing visual — the owner holds the screenshot gate.

---

### 2026-09-11 — Three surfaces built by Gemini under orchestration (Claude)

First batch of the 42 remaining artboards, and the first built by a
non-Claude implementer. Gemini 3.1 Pro took `1l`/`1z`/`1bb`, Gemini 3.8
Flash took `1aa`, each in its own worktree off `a6a43f30`. A Sonnet agent
held `1u`/`1v`/`1w`/`1x` and produced nothing before its session limit, so
those four remain open.

**Reviewed by running, because both commits claimed gates they had not
passed.** Group B carried a lint error, fifteen new warnings and trailing
whitespace that fails `verify.sh`'s whitespace gate, while its message said
SwiftLint had been run. Group C was clean. Everything landed only after the
full suite (1,750 tests, 1,748 passed, 0 failed), `Scripts/lint.sh` exit 0,
and macOS Debug and Release builds ran here on the merged result.

**What the review changed** (`40250315`, details in its message): 1z had
taken the form family but kept its navigation title under a wash that
empties titles, and had no header block, so it named itself nowhere; it is
now the same List + `cardList()` shape as 1ac. Its footnote described
account rows this screen does not have. 1aa's archive footnote described the
section above it, and its URL force-unwrapped.

**The lesson is the routing one.** An implementer that cannot run the gates
reports success from reading, which is the failure this file already records
for agents without a toolchain — the difference now is that the reviewer can
run them. Both groups' *layouts* were faithful: 1aa's header and its seven
row titles match the artboard exactly, checked against the outline tool.

**Not seen running.** 1l and 1z need a signed-in AO3 session, which no agent
here has; 1aa is reachable signed out. The screenshot gate is unmet for all
three.

---

### 2026-09-11 — T-215.1 finished, and Codex's T-215 commits reviewed (Claude)

**Started by Codex, finished by Claude.** Codex hit its usage limit partway
through T-215. Its three commits (`18c95b77`, `4465fe02`, `ee82191e`) were
pushed; both worktrees were clean and its old checkpoint is stashed. What it
had not finished was the upgrade check in `18c95b77`. On its simulator
(`KudosCodexHandoff20260911`) it had installed a `39e7eefa` build and saved a
"Doctor Who" search at 16:39, then stopped while trying to open Search.

Claude finished it on the same data container. The `39e7eefa` build did **not**
crash; its Search tab showed the empty state although the store held the row,
which fits a fetch that fails quietly. (The column held NULL, not the empty
blob the tests hit, so the tests' crash is one path, not the only symptom.)
A fixed build (`a0143951`, no `fandomUnion`) was installed over the same
container. It launched without crashing, and SwiftData migrated the store: the
`ZFANDOMUNION` column is gone and the saved search's row is intact.
**Not seen on screen:** synthetic taps did not reach the floating tab bar on
that simulator (Codex hit the same), so the list was not visually confirmed.
The old store snapshot and screenshot are in the Mac worktree's gitignored
`build/mac-verify-2026-09-11/upgrade-check/`.

**Review of Codex's code** (cross-family, rule 1). Codex built none of it
locally ("the simulator build is still running"). Checked here by running:
CI's app build and lint are green on `ee82191e`, and the full iOS suite runs
on it: 1,746 tests, 1,744 passed, **0 failed**, 2 skipped, Codex's new slider test
included.

- `ee82191e` ✓ — a pure move: counted as multisets, 75 lines relocate with no
  added-only line, and the only removal is the two-line orphan comment the
  handoff asked for. SwiftLint passes.
- `4465fe02` → fixed in `da8b04d9` — the clamp-before-convert helper, the
  pinned drag scale and the `@GestureState` reset are right. One edge came with
  the old code: on a zero-width track the first drag sample is `0/0`, and
  `Int(NaN)` traps because NaN fails both clamps. Now a no-op, and pinned in
  Codex's test.
- `18c95b77` ✓ — its release claim checks out (b0aeeb41's IPA run succeeded
  and published).

**Left open for Codex:** Claude's commits on this branch are unreviewed by any
other family: `e7612188`, `769406d7`, `4ec714ce`, `a0143951`, and this one.

---

### 2026-09-11 — T-215.3: reader lint gate (Codex)

Moved 86 physical lines of computed helpers into the existing same-file iOS
extension, without changing their bodies or access. Removed the orphan finish
comment above `isPhone`. The struct is now 899 lines by SwiftLint's count.
`Scripts/lint.sh` exited **0** (warnings remain); log `/tmp/kudos-handoff-lint.log`.
No reader behavior or stored properties changed. Simulator behavior remains
pending. The initial XcodeBuildMCP call timed out after 300 seconds while its
xcodebuild process continued compiling; that timeout is not a build result.

---

### 2026-09-11 — T-215.2: extreme range bounds (Codex)

Ported only the requested slider, test and architecture hunks, plus the
ReadingLogService comment. Kept HEAD's `niceCeiling` and all persistence fixes.
Movement clamps before converting to Int; the scale stays pinned during a drag.
`@GestureState` resets the pinned maximum on cancellation as well as completion.
The text fields now expose distinct From/To accessibility labels.

Ran a Swift probe extracted from the production arithmetic with To =
8,000,000,000,000,000,000, twenty increments and off-track movements: passed.
Swift parsing passed. Added the regression to SearchFiltersTests; the full iOS
suite and actual VoiceOver/drag interaction remain pending the simulator build.

---

### 2026-09-11 — T-215 owner handoff, release and upgrade verification (Codex)

Saved the old tracked checkpoint to `~/codex-checkpoint-2026-09-10.patch`,
copied its untracked review alongside it, and preserved the complete state in
a named git stash before fast-forwarding the `191e` worktree to `b0aeeb41`.
The original checkpoint remains recoverable; only the owner-listed hunks will be ported.

Confirmed the rolling release now targets `b0aeeb4111e5b18e3c5cf166a27f5f7c1865ad19`
and carries `Kudos-b0aeeb4.ipa` (SHA-256
`0b55587f856c659f47fd101b9e2bae7a1952eaf24bebb3a2197acbed7f14ef57`).
[Unsigned IPA run 34640150956](https://github.com/cidy02/kudos-ao3-reader/actions/runs/34640150956)
completed successfully, including publishing the replacement release.

Created an isolated iPhone 17 Pro Max / iOS 26.5 simulator,
`KudosCodexHandoff20260911` (`730F4C6C-6DC0-498D-A2B8-843841E94CF2`).
The `39e7eefa` build is compiling in the clean detached `e63d` worktree, with
DerivedData under `/tmp/kudos-codex-handoff-derived`. The app upgrade check is
**pending**, not inferred from the successful fresh-store tests or IPA build.
Signing settings are unchanged. Remaining tasks proceed while that build runs.

---

### 2026-09-11 — First run on a Mac: what failed, and what was fixed (Claude)

Every gate ran for the first time. What they found, by origin:

| Found | Origin | Fixed in |
|---|---|---|
| Every saved search fails to load; faulting one crashes (`fandomUnion` stored on `AO3SearchFilters` but missing from its `CodingKeys`) | `5132f943` | `e7612188` |
| KudosTests does not compile (6 errors, two test files) | `bac33974` | `769406d7` |
| History buckets ignore the injected `now` | `eadb05b2` | `769406d7` |
| Challenge `isMatched` false on every path | `561f848b` | `769406d7` (rule only) |
| Insights test compares `Double?` to an Int; bulk-edit test pins the destructive POST `a2c4f5e3` removed | `cffc1fca`, `bac33974` | `769406d7` |
| Three `large_tuple` lint errors | `561f848b`, `bac33974` | `4ec714ce` (Codex's fix, ported) |
| macOS: 9 unguarded TTS files, `.bottomBar`, sherpa-onnx without `platformFilter`, a stale entitlements grep, Release DerivedData under iCloud | before the base | `a0143951` |
| Missing sherpa-onnx / onnxruntime notices | before the base | `a0143951` |

**After the fixes** (`a0143951`): full iOS suite 1,745 tests — 1,743 passed,
**0 failed**, 2 skipped (opt-in Kokoro corpus); `check-invariants` OK;
SwiftLint 1 error (`ReadiumReaderView`, inherited); `build-macos.sh` Debug and
Release build, product check fails on the ad-hoc signature only.

**The SavedSearch crash shipped** in the public rolling IPA (`Kudos-39e7eef.ipa`);
the next build from this branch replaces it. The mechanism is now a rule in
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md`: SwiftData gives every stored
property of a composite a column but fills the columns through `Codable`, so
a property left out of `CodingKeys` gets a column nothing writes. Both halves
were checked by running (remove the field → green; key it → green).

**Answered against live AO3** (transcripts in `build/mac-verify-2026-09-11/ao3-live/`):

- The family union. An autocomplete `id` is the tag *name*, so it is not the
  filter id; numeric ids are on each tag's works page (feed link, sidebar).
  `work_search[query]=filter_ids:(A OR B)` is an exact union — Doctor Who
  (2005) ∪ (1963) = 68,057 = 61,248 + 9,958 − 3,149 — and composes with the
  other space-joined clauses. `fandom_names` gives the 3,149 intersection,
  which is what family pages show today. **Not wired yet.**
- `1aa`'s seven archive paths are all otwarchive routes (`routes.rb`) and
  AO3's own nav/footer links; five returned 200, `/content` and `/donate` hit
  Cloudflare 525 three times that day. **The screen is not built yet.**

**Confirmed, left for the owner:** `setFavorite` has no caller, and the
Abandoned bucket cannot populate (it needs `hasEPUB`, History selects
`!hasEPUB`).

**Open, found in passing:** `FilterRangeSlider.swift:106` and `:120-121` still
trap on bounds near `Int.max` (Codex's checkpoint has the fix);
`parseChallengeAssignmentsPage` matches no real otwarchive markup and its test
fixture is invented, so 1bz's matched state is wrong on real AO3 regardless of
the rule fix. Codex's uncommitted checkpoint is otherwise superseded — do not
port its `KudosBackup` or `ReadingLogService` hunks; they would undo
`8b892f1e`, `39e7eefa` and `a2c4f5e3`.

---

### 2026-09-11 — Phase 10: the collections UI Grok's networking had none of (Claude)

`561f848b` landed `AO3Client+Collections` and `AO3CollectionActions` — a
comprehensive layer with **no UI at all**. `1r`, `1bm`, `1ci` and `1bl` are that
UI. `1s` (the staged manage-items screen) is what is left.

**Unknown is not zero**, and it is the rule the 1bm sort turns on. A collection
whose works count failed to parse is not a collection with no works; one whose
date will not parse is not the oldest. Ranked rows sort first, unrankable ones
hold AO3's own position after them. Treating a missing count as 0 would put a
collection nobody can see the size of at the bottom of a size-sorted list, where
it reads as a fact.

Recently updated parses AO3's printed date, and that is a **format assumption,
not a guarantee** — scraped text the app has never parsed anywhere else. Four
shapes under a fixed `en_US_POSIX`/UTC formatter so a device in another locale
cannot reinterpret AO3's output; anything else returns nil and holds position.
*If Recently updated ever looks unsorted, `AO3CollectionsFilter.updatedDate` is
the first place to look.*

**Two spec controls are absent, each with its reason on screen:**

- 1bm's **My role** (Maintainer / Member / Invited). `AO3Collection` carries no
  role and the collections page gives none; finding out is a participants
  request per collection — a page load per row, for a filter. The panel says so.
- 1ci's **Gift** badge. `AO3WorkSummary` has no recipient and the collection's
  works page prints none. The recipient *does* reach the app as
  `AO3CollectionItem.recipient` on the maintainer's items page, which is 1s —
  a different request, a different screen, and where it can be drawn honestly.

**Anonymous is the collection's state, not the work's**, so the badge sits on
the card rather than replacing the byline. Matched against the whole byline
case-insensitively, so a creator called `anonymously_yours` is not badged.

1ci's three segments are three AO3 pages and load independently — the spec's own
note — which also means opening the screen costs one request rather than three
when a reader only looks at Works.

**The 1bl form is fetched, never invented.** `collectionNewForm()` and
`collectionEditForm(slug:)` both live in `AO3CollectionActions`, per the
networking policy: the form carries hidden fields and a CSRF token that have to
come from the page AO3 served. `collectionEditForm` was `private` and is
internal now. `AO3CollectionForm.blank` is new — every field on that type is
non-defaulted because a form is normally *parsed*, so a screen needing something
to bind to before its fetch lands had no way to make one.

An invalid save **does not discard the edit**: AO3 returns the whole form with
errors attached, which `.invalid` carries, so the reply replaces the form and
the errors render against their own rows. Name availability is one request per
settled name on a 600ms debounce, creating only, with the format checked locally
first so an obviously invalid name never becomes a request.

Closing and deleting stay Open-on-AO3. Neither is reversible from the app.

Services still has exactly **two** `URLSession` constructors.

---

### 2026-09-11 — Subscriptions' badge, and the store it needed (Claude)

`1p` was the one Phase 6 screen with a real capability gap rather than a
restyle. The list already went through `AO3AccountWorksList`'s 1o header; the
"X New" badge needed a per-subscription last-seen mark, and no such store
existed.

**Two decisions worth disagreeing with, so both are written down.**

*Chapter counts, not dates.* `AO3WorkSummary.dateUpdated` is prose ("Updated 3
Sep 2026") and would have to be parsed back into a date in AO3's locale before
it could be compared. The posted chapter count arrives already parsed, is what
the reader cares about, and is the signal `SavedWork.knownChapterCount` already
uses for update detection.

*`UserDefaults`, not a new `@Model`.* A model means a schema change, a
`PersistenceSync` entry, a preview-container entry and three `KudosBackup`
sites — none exercisable from this container, and **T-211 forbids the manifest
bump** that would normally carry it. What is stored is a per-device convenience:
losing it re-baselines the badges and loses nothing anyone authored. If it
should survive a restore it moves to a model later, and
`SubscriptionWatermarks` becomes the migration source. Bounded at 512.

Three badge rules, each pinned by a test because each would annoy a reader if it
went the other way:

1. **A work never seen before does not badge.** Otherwise opening this screen for
   the first time meets three hundred badges, every one technically true and
   collectively meaningless. First sight baselines instead.
2. **`baseline` only ever adds**, so a badge survives the page load that draws
   it rather than being cleared by it.
3. **Counts only go up**, since AO3 chapter counts fall when a chapter is
   deleted.

Clearing is an explicit **Mark All as Seen** in the overflow rather than
something the page load does — a list that marked itself read on sight would
clear the badge before the reader could use it. Per-row clearing on open wants
the row's own tap handler threaded through `EnrichingAO3WorkRow`; that is left
as separate work rather than bodged in.

The badge draws on **both** row branches. A subscribed work already in the
library renders through the local branch and is the one most worth telling
someone about — they can open it now. Found by reading
`CanonicalWorkMerge.remoteLed`, which keeps `.remote` on paired entries, so the
count is available either way.

---

### 2026-09-11 — Phase 9 finished except the blocked one (Claude)

`1bj`, `1ah`, `1ai`, `1aj`, `1ak`, `1bd` all landed. `1bc` (Favorites — fandoms)
is the one left, and only its "with new work" half: that needs a fandom-page
newest-works parse that does not exist. The **fandoms scope itself is built** —
it is the same derived list as authors and tags.

**Recently Deleted (`1bj`) groups by how long is left, not by type.** Nothing is
lost by regrouping because each row names its kind in its kicker, and a queue
expiring in three days belongs next to a work expiring in three days. The spec
says the window is 30 days; the app's is 90, and the header reads
`PreservedWorkService.recoveryWindow` so the screen cannot promise a window the
code will not honour. String sweep: every affordance intact (swipeActions 2→2,
contextMenu 1→1, confirmationDialog 3→3), and the only strings dropped are the
three type section headers the kickers replaced.

**`1ah`/`1ai` are one screen with a Time / State / Fandom / Flat strip.** Rules
in `LibraryHistoryGrouping`, pure over works, nine tests.

> **A section that can never populate, left in deliberately.** The Abandoned
> bucket cannot fill on today's Reading History shelf.
> `ReadingLogService.isAbandoned` requires `isInProgress`, which requires the
> EPUB on disk; `LibrarySectionKind.history` selects `!hasEPUB`. They never
> overlap. Widening the shelf here to light it up would change what Reading
> History *contains*, which is not a screen's call to make — so the bucket stays,
> "Read, not finished" is the one that fills, and this is the note for whoever
> decides whether the shelf should widen.

**Favorites (`1aj`/`1ak`/`1bd`) scopes are derived, not starred**, which is the
spec's own reading: its rows say "6 works read · 31h 12m", which the app
computes. A star list would be empty for every reader who has not curated one.

> **Finding: the explicit star is built and unreachable.** `ReadingFavorite`
> carries `.author` / `.fandom` / `.tag` kinds and
> `ReadingLogService.setFavorite` writes them — and **`setFavorite` has no
> callers anywhere in the app**. Works meanwhile use `SavedWork.isFavorite`, a
> separate boolean, which is what the Favorites shelf and every star button read.
> Two stores for one idea, one of them dead. Nothing here writes either. Someone
> has to decide whether `ReadingFavorite.work` replaces the boolean or the
> author/fandom/tag kinds get dropped; doing it silently while building a screen
> would be the wrong way to settle it.

**The mature gate applies to derived rows**, which is not obvious and is worth
stating: affinity rows come from works filtered through `passesPrivacy`, because
a row naming the author or tags of a hidden work puts back exactly what the gate
took away, one screen over. Same class of leak as the one Insights had.

Two new shared pieces, both made to stop a drift rather than to be tidy:

- `ReadingLogService.summaries(in:)` — the whole log in **one** fetch. The
  per-work helpers each fetch the entire session table, which is fine for a
  detail screen asking about one work and quadratic for a history list asking
  about three hundred. Gated on History so the other six sections do not pay for
  it.
- `SavedWork.isOnSavedForLaterShelf` — a test caught `ReadingAffinities` checking
  queue membership while the shelf's actual rule is membership *or* the legacy
  `isSaved` flag. A row reading "3 in Saved for Later" that disagreed with a
  shelf showing two is a bug nobody could explain from either side.

Counts in `ReadingAffinities` deliberately **over-count** against a grand total,
unlike `ReadingInsights`' fandom shares which **partition**. Worth writing down
because the two sit one tap apart and look like the same arithmetic: a share of a
fixed pie has to sum to the pie, while "N works read carry this tag" is a count
about that tag alone, and a work with two tags is honestly counted by both.

---

### 2026-09-10 — Reading Insights takes artboard 1bi, and stops being two screens (Claude)

Phase 9's data path landed with Grok (`725695e3`) and nothing surfaced it. 1bi
is the screen that does, and it turned out the app already had one.

**`ReadingStatisticsView` existed, titled "Reading Insights", reached from
Library's "…" menu.** I wrote a second screen before checking — §2 step 2 says
to check what exists before naming anything new, and I skipped it. The two are
now one. What made the old screen worth replacing rather than extending is in
its own doc comment: *"The app does not track sessions or per-word progress, so
'words read' counts only finished works whose AO3 word count is known."* That
was true when it was written and stopped being true when `ReadingSession`
landed. It was a screen built around a constraint that no longer holds.

`ReadingInsightsView` is 1bi: the month's hours with a delta pill and a
seven-week bar chart, where the hours went by fandom, and four figures of pace
and follow-through — all on `SubjectCardBackground` in the Library scope's hue.
**Its fourth card is not in the artboard.** The old screen's figures (works
opened, words read, still in progress, opened in 7/30 days, last read) survive
there, because the density gate counts dropping them as a regression, and
because they answer a different question: the three spec cards measure
*reading*, that one describes *the shelf*. A reader with an empty log still has
a library, and that is what they see.

`ReadingStatistics` (the model) and its five tests are untouched — only the view
was replaced.

**The mature gate turned out to matter.** The screen takes `works` as a
parameter rather than running its own `@Query`, because Library passes
`statisticsWorks`, which already excludes queue-only works and adult works the
gate is hiding. A bare `@Query` would have named a hidden work's fandom on this
page. The hours still count either way: sessions are read from the store
unfiltered, and a session with no matching work has no fandom to attribute, so
it lands in `Everything else`. Right answer, and it falls out rather than being
arranged.

`ReadingInsights` holds every rule, over `ReadingSessionFacts` — a plain value
extracted from each row. Two reasons: `ReadingSession` is a `@Model` and so main
actor-bound, which would drag the arithmetic onto the main actor with it; and a
rule taking plain values can be tested by writing four of them in a line instead
of standing up an in-memory container to assert that a median is a median.
Thirteen tests, no `ModelContainer`. The arguable choices are each pinned by a
test that would fail on the other answer:

- **median, not mean** session length — one four-hour binge must not move the
  number answering "how long do I usually read for";
- **finish rate per work, not per session** — a much-reread favourite would
  otherwise carry the whole figure;
- **streaks count days, not sessions** — two sessions in one evening are one
  day, and the calendar is a parameter because "which day is this" is a
  timezone question;
- **fandom shares partition the hours** — each session's time goes to one
  fandom, the work's first, so the shares sum to the total printed above them.
  Counting a crossover once per fandom would print shares adding to more than
  the whole.

`ReadingLogService.wordsPerHour` now delegates to `ReadingInsights` so the
screen and the helper cannot report two different rates for the same rows.

**A spec-vs-code disagreement, resolved toward the code.** 1bi's footnote says
"Sessions shorter than a minute are not counted". The log's actual floor is
`ReadingLogService.minimumPersistableDuration`, which is 15 seconds. The screen
builds the sentence from the constant, so the two cannot drift the next time
anyone tunes it.

`SubjectCardBackground` / `.subjectCard(palette:)` is new, made shared at the
**third** inline copy of the same four lines (`WorkLedgerRow`,
`LibraryView.ledgerRowBackground`, and 1bi's three cards). Written as one
`.background` holding a surface with the wash overlaid, not two chained
`.background`s — chaining stacks backwards and the wash would land behind the
opaque surface, which is exactly the bug `ed3eacb` fixed on five screens and
which I re-created here on the first attempt.

Three more defects caught by re-reading the diff rather than by a compiler: a
`@ViewBuilder` property typed `(some View)?`, which is not a thing; a
`fandomRow` parameter named `share` shadowing the `share(_:of:)` method it
called; and `ReadingStatistics.init` — a full walk of the library — being read
through a computed property seven times per render.

**Left in Phase 9:** `1ah`, `1ai`, `1aj`, `1ak`, `1bc`, `1bd`, `1bj`. The
Abandoned and favourites rules already exist in `ReadingLogService`.

---

### 2026-09-10 — Phase 6 opens: Privacy takes artboard 1ac (Claude)

`ca9b158` is **green** (run 39, 9m59s) — the reading-session durability fix and
the bounded fandom count cache both compile.

Phase 6 is next per §3c, and `PrivacyDataView` is its cheapest real screen: 129
lines, one call site, no network, and the form family already draws everything
1ac asks for. It is now the kicker / rule / 32pt title / tally header at the
16pt account gutter, two `SectionRuleHeader` groups over `subjectPanel()` panels
of `SubjectFormRow`, and the spec's own footnotes.

**The figures are measured, not described.** The old screen said the right
things — "everything stays on this device", "safe to clear" — and gave the
reader no way to check any of them. 1ac prints `412 MB`, `318 works`, `6`.
`Services/LocalDataFootprint.swift` walks Works, Originals, Fonts and the two
cache directories off the main actor and reports allocated size where the
filesystem gives it, so the number matches what iOS Settings would say about the
same bytes. The counts come straight from the store. A privacy page is the one
page where "take our word for it" is the wrong ask.

**Two spec rows had no data and were answered honestly rather than faked.**
1ac's "Search history · 84 searches" has no store behind it: the app keeps no
search history at all, and `SavedSearch` is a search the reader *named*, which
is their content, not a log. The row says **Not recorded** and there is no clear
button — on this screen that is the better answer. `SavedSearch` gets its own
row as "Saved searches", which is a true local-data figure.

**Two sections the spec omits were kept**, per `AGENTS.md`'s density gate: the
Voice Pack paragraph (the app's only statement of what a model host does and
does not receive) and the AO3 session row (where credentials are removed).
Dropping them to match the artboard would have dropped the two hardest privacy
facts on the page.

`Services/LocalDataClearing.swift` holds the bulk clears as `select…` + `clear…`
pairs. The count in each confirmation dialog is produced by the same rule that
does the work, so the number the reader agrees to cannot drift from what
happens. `selectFreeableDownloads` reuses `SavedWork.isProtected` rather than
restating its four conditions, so this button and the reader's own auto-free can
never disagree about what is safe to drop; `clearReadingPositions` deliberately
leaves `lastReadDate` alone, because that is the Library shelf's ordering rather
than a position inside a file.

`SubjectFormRow` gained `isDestructive`. A caller cannot tint the row from
outside — the label sets `.primary` internally and wins — so tinting from the
call site yields a red chevron over a black label. Spec 1ab's "Sign out" wants
the same flag.

Six tests in `KudosTests/LocalDataClearingTests.swift`, each written to fail if
its rule is reverted. **Not run:** CI compiles the app target only.

**Left in Phase 6:** `1aa` More on AO3 is drawn but partly blocked — the spec's
fourth section ("The archive": support, report abuse, ToS, content policy,
privacy policy, FAQs, donate) needs seven site-wide AO3 paths, and **they cannot
be verified from this container.** `archiveofourown.org` is blocked by the agent
proxy (every probe returns `000`) and `otwarchive/otwarchive` cannot be attached
to this session to read its `routes.rb` (cross-owner adds are refused). Writing
them from memory is exactly the failure this file already records three times —
a claim written from reasoning rather than from a primary source. They need the
owner, or a session with network reach, before that section ships. The first
three sections of 1aa use user-scoped suffixes the code already proves.

`1ab` Settings is `ReaderOptionsForm(includeAppSettings: true)`, shared with the
reader — converting it touches both surfaces and is not a one-screen change.

---

### 2026-09-10 — Grok T-214: gating capabilities + Codex "Needs building" notes

Codex hit a usage limit; both briefs landed here. **Extend only — nothing was
deleted to go green.** `project.pbxproj` was not touched (a local Xcode reorder
of FluidAudio/sherpa pins was reverted before it could commit — T-208's shape).
Services still has exactly two `URLSession(` constructors (`AO3Client`,
`AO3AuthService`). No `softDelete`/`hardDelete` in the new write files. Backup
manifest stays **v8**; new arrays are decode-if-present. Android will strip
them until a passthrough lands (T-210 class; T-211 forbids a v9 bump).

**Landed (data / networking, not screens):**

- Local reading log (`725695e`): `ReadingSession`, `ReadingFavorite`,
  `FandomReadWatermark`, `SavedWork.keepInProgressOverride`, tombstones,
  `ReadingLogService` (drop opens < 15s), reader appear/disappear hooks on
  iOS Readium + macOS `ReaderView`. Not `applyDebouncedReadiumLocator`.
- AO3 collections + challenges (`561f848`): reads through
  `getHTML`/`authenticatedPageHTML`; writes are CSRF + single `submitWrite`.
  Matching and tag-set association are `matchingOpenOnAO3` /
  `associationOpenOnAO3` only — no `runMatching()`.
- AO3 writing surfaces (`bac3397`): work/chapter/series/draft/bulk/tags.
  Tag autocomplete wraps the existing `autocompleteTags` (debounce +
  coordinator). Non-canonical tags still post. `/series/new` has no title
  field, so create is Open on AO3.
- Fandom families (`a0913bf`): group on parsed title inside one category;
  identity is sorted original names joined with U+001E. Family tap sends every
  raw sibling as an included fandom filter. Sum carries a tilde until
  `AO3ResultSummary.total` is cached. `MediaBrowserView`'s category work total
  is the same lie, now marked approximate.
- Filter UI (`5100add`): `includeColor` (not `.tint`), searchable language
  picker, five range sliders over existing From/To strings (digits-only still
  strips non-ASCII), Library filter-collision empty state with per-drop
  counts, series empty → Safari.

**Confirmed matching / stale, built nothing:** `1ao` `1aq` `1as` `1au` `1av`
`1aw`. `1ba` ("posting comments is an AO3 write the app does not implement")
is stale — `postComment` exists. `1ax` SavedSearch naming alert and idle list
already exist.

**Verified:** `Scripts/swift-parse-check.py` on the 54 Swift files in this
merge — 0 syntax errors. Grep: two `URLSession(` in Services; no file
deletions vs `origin/codex/kudos-redesign`.

**Not verified:** no `xcodebuild`, no simulator, `KudosTests` is not compiled
by CI, writes never hit a live AO3 session, nothing seen on a device. Tests
were written to fail if the feature is removed (duration, UUID grouping,
includeColor ≠ excludeColor, drop-one counts, family id ≠ title) but that
mutation check was by reading, not by running.

**Left for screens:** Phase 9–12 layouts, `1bv` editor (mockup), `1bb`, the
Search paging pill.

### 2026-09-10 — Verification pass over Grok's and Codex's work

Ran mechanically rather than by reading: a string sweep for removed
affordances, a diff of interaction modifiers, a token comparison against §1,
and a targeted check of every claim the two made.

**No features were dropped.** 31 user-facing strings disappeared across 88
commits; all but two are section headers absorbed by the figure strip, facts
card and tally strip. Of those two, `"See all in progress"` was an
accessibility label replaced by `SectionRuleHeader`'s own `"See all \(title)"`,
and `"Saved for Later in Kudos"` was the header disambiguating the local shelf
from the AO3 one, correctly gone with the approved split. Interaction
affordances show no net loss anywhere — `swipeActions` 0/0, `contextMenu` 0/0,
`ToolbarItem` 3/3, and `searchable`, `Menu` and `onDelete` each gained one.

**One real density change, and it is the spec's.** The ledger rows that
replaced standard rows on Home, Library and Account show six fewer facts by
default — language, comments, kudos, bookmarks, hits, published date. All are
reachable through the row's disclosure, which Codex made always-available by
widening `isExpandableWork` to `presentation == .ledger || …`. Before that, a
comment of ours claimed a ledger row "has no summary and no tag groups, so
there is nothing for an expand control to reveal", which was wrong and would
have left those six unreachable on three screens.

**Spec tokens all match**, including through Codex's `@ScaledMetric` pass,
which preserved the spec bases exactly: 32, 15.5, 11, 16.5, 11.5.

**Grok's claims all verified true** — the v8 manifest decodes older archives
through a custom `init(from:)` using `decodeIfPresent`, all three new models
reach all three export call sites, restore inserts them with snapshot ids,
deletions are tombstoned, and `FandomFamily.id(originalNames:)` sorts original
names rather than the parsed title.

**Two defects found and fixed** (`ca9b158`):

1. **Reading sessions were lost whenever iOS reclaimed a backgrounded app.**
   The row was written only by `endSession`, which runs from the reader's
   `onDisappear` — and that never fires when the OS jettisons a backgrounded
   process. The bias ran the wrong way: the longer the session, the likelier it
   vanished, so "hours read" would have undercounted invisibly. `pauseSession`
   now writes the row too, both writers going through one `persist()` keyed by
   a `recordID` fixed at session start so a resumed visit stays one row.
2. **`FandomFamilyExactCountCache` was unbounded.** Capped at 128, oldest-first,
   matching the ceiling the networking policy names twice. No TTL, deliberately
   — it holds a work count rather than page HTML.

**What the pass cannot tell you**, unchanged and now larger: 2,150 lines of
tests CI never compiles, 42 write call sites never exercised against live AO3,
and no screen seen on a device. The density change above is exactly the kind of
judgement that needs eyes rather than a grep.

### 2026-09-10 — Codex's T-213 pass (`74680bb`), and what it found in ours

Committed by the owner as `wip - codex hit usage limit`, so it is a cut-off
session's work rather than a finished one. It parses clean and its call sites are
consistent; what it lacked was the bookkeeping, which this entry and the rows
below supply.

**It disproved a claim we had made three times.** The resume card said the
chapter's title was unavailable because `SavedWork` stores only a spine index.
Readium's persisted locator carries the publication's own label, and
`WorkReadingPosition.title(from:)` reads it — so the card names the real chapter,
and front matter ("Preface", "Afterword") verbatim instead of inventing a number
for it. Tested, including the invalid-locator fallback. **That is exactly the
trap this file warns about in two other entries, and we were the ones in it.**

**It fixed an accessibility gap in the shared components.** `SubjectHeaderBlock`,
`SectionRuleHeader` and `WorkLedgerRow` were built with fixed point sizes and
`lineLimit(2)`. They now use `@ScaledMetric`, unclamp their line limits at
accessibility sizes, wrap the header subtitle in a `FlowLayout` instead of an
`HStack`, and swap the ledger row's `HStack` for a `VStack` through `AnyLayout`.
The codebase's own `HomeResumeHero` already did this; the redesign's components
did not follow it.

**It reworked `SensitiveWorkRow`'s navigation flag** — `providesNavigation: true`
became `usesInlineNavigation: false`, with `contentInsets` moved inside the
privacy boundary so tapping a card's padding reveals and selects exactly as its
content does. The polarity flip was applied completely: no stale callers remain,
and the single opt-in is the Library dashboard's `ScrollView`.

**It separated Saved for Later from AO3's Marked for Later.** Library's shelf had
merged the local queue with the user's AO3 Marked-for-Later list; the two are now
distinct, with AO3's list living only in Account. Kept at the owner's direction.
**Recorded as a deliberate divergence, because the artboards say otherwise:** 1c
lists *"Saved for Later (local + the AO3 'Marked for Later' card …)"*, 1d lists
*"the AO3 'Marked for Later' row"*, and both draw it as an ordinary work
card/row carrying a small **"AO3" badge** at the top-right (radius 5, black 40 %,
`700 8px`, `.08em`, white 80 %). What the spec does support is the framing —
its own build note calls Saved for Later "a permanent queue that happens to be
reachable here". No AO3 provenance badge exists anywhere in the app, which may be
why the merge read as confusing enough to remove. **Open work:** if the shelf ever
merges again, it needs that badge first.

**What T-213 said it would verify and did not:** the iOS suite, SwiftLint, the
macOS build, and theme/accessibility screenshots. None can run from this
container — no toolchain, no simulator — so they remain unrun, not merely
unreported.

### 2026-09-10 — Audit of the Codex review, and finding 6 paid

Both Codex commits (`38c42f4`, `7fac768`) were reviewed in `9ee86ba`; rule 3
closes them. What was *not* done was checking whether that review's findings
still hold, which is worth doing before a branch merges — a recorded fix can
regress, and a recorded debt can grow.

Verified against today's code:

| # | Finding | State |
|---|---|---|
| 1 | Card wash shifted hue between stops | ✅ every `Color(hue:)` in `SubjectSurface` takes the same `hue`; no `+0.08` anywhere |
| 2 | Signal tray on `.ultraThinMaterial` | ✅ gone; the only remaining mention is an unrelated comment |
| 3 | `updateBadge` accent-on-material | ✅ white on `glassFill(0.16)`, with the reason in the code |
| 4 | `.padding(-12)` after `.minimumHitTarget()` | ✅ no negative padding survives anywhere in the app |
| 5 | Kicker `+N` took the accent | ✅ `.secondary` |
| 6 | Duplicated metadata-line logic | ❌ **still open, and it had grown** |

Finding 6 was recorded as "a reuse debt, not a bug. Noted, not yet paid." In the
meantime a **second, byte-identical** copy appeared: `HomeResumeHero`'s
`metadataSegments` and `WorkRow`'s `ledgerMetadataSegments` were the same eight
lines under two names. Both now call `WorkStat.localWorkMetadata`, which takes
values rather than a `SavedWork` so it is a pure function with tests that need
no model context.

**The lesson is about the ledger, not the code.** A finding recorded as "noted,
not yet paid" reads as closed at a glance — the row says *reviewed*. This one sat
for a dozen commits and quietly acquired a second instance, which is what an
unpaid formatting debt does when nothing is tracking it. A finding that is
deliberately not fixed needs to be visible as *open work*, not as a footnote on a
row marked reviewed.

Finding 6's original target is still open too: `AO3WorkRow.ledgerMetadata` and
`WorkListStatsRow` implement the same zero-suppression rule over the same
`@AppStorage("showsZeroStats")`. They are not byte-identical — one takes an
`AO3WorkSummary` and one takes optionals — so unifying them is a real
refactor rather than a deletion, and it is left as named open work rather than
attempted alongside a review.

### 2026-09-10 — Artboard 1a screen 1, complete

Every block the artboard draws, in its order: fandom kicker · 32pt title ·
byline, the rating·warnings·category·chapters strip, the resume card, the serif
summary, the ON AO3 chips, the tag clusters, the grouped facts card, the
kudos·comments·bookmarks·hits strip, the two outline buttons, and the My copy
row. All of it on the page wash; the only cards left are the ones the spec
actually draws as cards.

**The tag clusters lost their five stacked cards.** A work's classification is
one thing, and five cards made it read as five; the field label plus the chips'
own shapes already separate the groups. Spec 1a tints exactly one cluster —
relationships — and that is the accent staying scarce: the relationship is what
a reader picks a fic for, and if every cluster took the colour none of them
would mean anything by it. A count prints only where it says something the eye
cannot: two relationships are two chips, nineteen freeforms are a paragraph.

**Three cards went away without losing a fact.** Publication, Work and Stats are
absorbed — Rating, Category, Status and Chapters by the figure strip; Words and
Language by the facts card's headline row; Hits, Kudos and Comments by the tally
strip; Source and preservation state by `WorkProvenanceSections`, which already
states both further down. Comments keeps its behaviour by making a stat cell
able to act, which is what spec 1a's accented, glyph-bearing COMMENTS cell is
drawing in the first place.

**The segmented control is gone, and screen 2 exists** (`cc5a890`). Those were
always one change: 1a is one continuous page and the sheet's content is what the
Library tab held. Where the four segments went — Overview to the page itself,
Tags to the clusters in place, Discussion to a Comments group of form rows plus
the tally strip's accented cell, Library to the My copy sheet behind the row at
the foot.

The sheet carries `librarySections` unchanged. Moving that content from behind a
segment to behind a row is the change; rewriting it at the same time would have
made both halves harder to review, and it is already the set of facts artboard
1a screen 2 lists.

**Comments kept all three entry points** even though the artboard draws only
the accented cell. Chapter comments and Write a Comment are reachable from
nowhere else on the page, and dropping them to match a mock is the scanability
regression `AGENTS.md` forbids. This is the same call the facts card made, and
it is worth stating as a rule: **an artboard is a layout, not an inventory.**
Where the app knows more than the mock's example work, the extra goes in the
artboard's own chrome rather than being cut to fit.

### 2026-09-10 — Parts before screens, and what counting the canvas showed

**The owner redirected the approach mid-session:** build the shared elements
first, then the screens, rather than discovering parts screen by screen. §2 now
says so, and `Scripts/redesign-spec-inventory.py` (`f8c2ff6`) is what makes it
actionable — it counts how many artboards use each element shape, so "shared"
is a measurement rather than a judgement.

Three things fell out of the first run that were not visible from any screen:

1. **The two biggest unbuilt shapes are rows.** One padded row shape is drawn
   300 times across 26 artboards, another 127 times across 24. Both live in the
   form, filter and settings screens — Phases 5, 6, 11 and 12, roughly fifty
   artboards, built from about six shapes between them. Nothing in the
   screen-by-screen order would have reached them for a long time.
2. **Two apparent components are the platform's.** The tab item in 41 artboards
   is iOS 26's own floating tab bar, and the 36×5 grabber in 14 is
   `.presentationDragIndicator`. Both ranked high enough to look like major
   shared work; neither is ours. Checking what already exists — including what
   the OS provides — belongs *before* naming a type, and is now step 2 of §2.
3. **The wash default was right by measurement, not by luck.** 62 artboards
   draw the page gradient at exactly 380pt, which is `subjectWash`'s default.
   Artboard 1a's 620 is a genuine exception rather than a number someone
   guessed.

The general lesson matches the one two entries below: prefer the check that
*measures* over the one that reasons. The spec is a data set, and it will answer
questions about itself far more reliably than reading it will.

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

**~~Two facts 1a states that the app does not have~~ — one, and it was wrong.**
This entry claimed the chapter's *title* was unavailable and that `SavedWork`
stored only a spine index, so the card said "Chapter 3". **Codex disproved that
in `74680bb`:** Readium's persisted locator already carries the publication's own
label, and `WorkReadingPosition.title(from:)` reads it. The card now names the
real chapter — and front matter verbatim ("Preface", "Afterword") rather than
inventing a chapter number for it. Only the pages-left estimate is genuinely
absent. A work nobody here has opened still gets **no ring**, rather than a 0%
one that would claim a browsed remote work is being tracked.

**Left on artboard 1a**, in the order the page runs: the summary in its serif
face; the ON AO3 action chips (Kudos / Subscribe / Bookmark / Mark for Later);
the tag clusters as `SubjectChip` groups under field labels; the grouped
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
   is not guesswork. Budget ~10 minutes a round trip and push early.

   **Batch generously.** A failed build reports every error in one log, so one
   large batch that fails costs a single round trip to diagnose, while eight
   small green ones cost eight. Batch size is close to free, and the round trip
   is the scarce thing. Push, then keep writing — never idle waiting on a run.
2. **Re-reading your own diff before committing.** Three certain compile errors
   in `2d3696c` were found this way. `git diff` the *whole* change, not the file
   you just touched — see below.
3. **Running the thing.** The release step passed `bash -n` and still failed on
   the runner; executing it against a stub `gh` would have caught it in seconds,
   and did once that was tried.
4. **`Scripts/swift-parse-check.py`.** A real Swift parser (tree-sitter) run
   over the files you changed, in about a second. It replaces the brace-counting
   this list used to recommend at this slot — it knows the grammar rather than
   counting characters, so it catches an edit applied at the wrong anchor, a
   broken interpolation, a malformed declaration. It still cannot see a missing
   *member*, a wrong argument label, or a type mismatch, which are the errors
   that have actually reddened this branch. Ten minutes of CI is the right price
   for a type error and much too high for a stray brace.

   **The trap it cannot see, and this branch keeps setting.** Every screen here
   splits its view code across several files by convention, and `private` in
   Swift is *file*-scoped. A block declared `private` in one extension file is
   invisible to an assembling property in another, and the parser has no opinion
   about it. `cc5a890` failed on exactly this, four times in one go, the first
   time a page was assembled from blocks living in four files. If you write a
   property that names blocks from more than one file, none of them can be
   private — and the helpers *inside* each block still should be.

   No Swift toolchain can be installed here — `download.swift.org` is refused by
   the environment's proxy policy, and Ubuntu's `swift` package is OpenStack's
   object store, not the language. A parser from pypi is as close as this
   container gets, and 403 of 405 files parse clean, so the signal is real.

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

**~~Known gap, deliberate~~ — closed, and the premise was false.** This said
spec 1b's chapter title was unavailable because `SavedWork` stores only
`lastSpineIndex`. Readium's locator carried the publication's label the whole
time; `74680bb` reads it through `WorkReadingPosition`. The last-read date now
backs the label up for legacy records rather than standing in for it.

**This was wrong for two sessions, in three documents, and in the code's own
comments.** It is the same failure §3's later entries name twice over: a claim
that the app lacks data, written from reasoning rather than from a grep, that
then gets copied forward because it reads like a settled fact. `1ah`/`1ai` still
want a local reading log — a *history* of sessions is genuinely absent — but the
chapter title never depended on it.

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

### ⚠️ Open — 1bk local collections: a form the app never grew

**Needs the owner, because most of what is missing is behaviour, not layout.**
Phase 10 recorded `1bk` as done on the grounds that local collections "already
existed". The capability does exist. The screen does not: a local collection is
created through a single `TextField("New collection")`
(`Features/Library/Collections.swift:413`) and renamed through another, and the
artboard draws a form with four more parts.

What each missing part actually costs:

- **Description** — cheap and safe. `WorkCollection.description` already exists
  and already round-trips through backup; its doc comment says it is stored only
  so an Android↔iOS restore does not drop it, and that iOS renders it nowhere.
  Rendering it closes the gap and gives the stored field a reason to exist.
- **Colour** — a new stored property. Small, but a schema change.
- **Show on Home** — a new property *and* Home tab behaviour: the artboard says
  it "adds a shelf above Recently Updated".
- **Keep downloads** — a new property *and* a change to the cache sweep, which
  the artboard describes as exempting these works from it.

That last one is why this was not built unattended. Exempting works from the
sweep changes which files get reclaimed; wrong in one direction it strands
storage, wrong in the other it deletes a download someone meant to keep. The §4
policy allows deciding anything a commit can reverse, and a storage-reclamation
rule applied to a real library at 4am is not that.

**The decision:** build the whole form including the two behaviours, or take the
cheap half (description, colour) and record Keep downloads / Show on Home as
features the spec proposes rather than parts of the redesign.

### ⚠️ Open — the Writing scope: 1bt's groups vs. the 1u/1v/1w chip rail

**Needs the owner; the code is unchanged.** 1bt draws every scope as grouped
destination rows — for Writing that is Posted (Works, Series), Unposted (Drafts,
subtitled that AO3 deletes them after 30 days) and Performance (Dashboard).
Reading and Activity were built that way on 2026-09-13, because they still had
the pre-redesign `AccountScopeMenu` and nothing was lost by replacing it.

Writing is different: it was *already* redesigned, in the 1u/1v/1w batch, to a
`SubjectHeaderBlock` plus a `SubjectChip(.pill)` rail, and reviewed. Replacing a
reviewed pattern with a second reviewed pattern is a churn decision rather than a
fidelity one, and the unattended run declined to make it — the §4 policy allows
deciding anything a commit can reverse, but this one trades one shipped design
for another with no evidence either way.

Worth noting the inconsistency is real and predates this: since the 1u/1v/1w
batch, Writing has not matched Reading or Activity. Whichever way this goes, all
three should end up the same.

**The decision:** take 1bt's groups across all three scopes and retire the chip
rail, or keep the rail and record 1bt's Writing grouping as superseded.

### ⚠️ Open — comment threads: 1f's elbow rail vs. a model already dropped on device

**Needs the owner. The code is unchanged in the meantime, and that is a pause,
not a verdict.** This section's rule is that the artboard wins over reasoning
already in the code. The reason this one is parked rather than applied is that
what 1f contradicts here is not reasoning — it is an experiment that was already
run.

Spec 1f draws threads hanging off a hairline rail whose elbows tuck behind each
reply avatar, with the tree rendered inline. `CommentThreadRow.swift`'s own doc
comment records four styles compared on a real device under T-151/T-183 — an
elbow style, a straight style, a flat one-card-per-conversation variant, and the
one that shipped — and three were dropped with evidence. Every artefact that
screen went through (the width squeeze at depth, the fill ladder washing out, a
six-rail gutter) traced to the single decision to render an arbitrarily deep tree
inline, which is what 1f's rail requires. Real AO3 threads go deep — *The Queen's
Mercy*'s epilogue carries a ~10-reply chain, and AO3 itself caps nesting at
`COMMENT_THREAD_MAX_DEPTH: 5` — so the failure case is the common case.

What shipped instead: one card per comment in the app's card language, a
per-level indent with an accent-tinted elbow leaving the card's *bottom* edge,
and a structural depth bound — a conversation shows its root and at most two
direct replies, everything deeper reached through "Continue thread", which
pushes `CommentThreadScreen`. The bound is the design, not a tuning: only one
nesting level is ever drawn, so the hard cases stop existing rather than being
balanced.

**What 1f did win, applied 2026-09-13:** "REPLYING TO YOU", which the screen had
no equivalent of. It is the one piece of parentage a reader scans for, and a
drawn connector cannot say it — a line states that a reply answers the card
above, never that the card above is *yours*. It resolves from
`AO3Comment.editPath`, AO3's own per-session marker of the viewer's own comment,
rather than by matching a byline against the account name: a byline is a pseud,
so name matching misses every comment left under a non-default pseud and can
collide with a stranger's.

Two smaller pieces of 1f were not taken, both on correctness rather than taste:
its "N deeper replies" wording (the count includes a third and later *direct*
reply, which is not deeper — `boundedListCountsDescendantsNotDirectChildren`
pins what the number means), and its fixed 9pt kicker, drawn at `.caption2`
because it sits inside prose that scales.

**The decision to make:** rebuild the thread presentation to 1f and re-run the
device comparison that rejected it, or record 1f's threading as superseded by
T-151 and keep the artboard for everything else on the screen (which is what
2026-09-13 shipped).

### ✅ Resolved — the ledger row pins its ring and tray to the top corners

**Decision: the owner's, 2026-09-12**, and a deliberate deviation from the
artboard. Spec 1ad draws the ledger row's ring-and-text group as
`align-items:center; gap:13px`, so the 44pt ring sits vertically centred. The
row now aligns `.top` instead, which pins the progress ring to the top-left and
the four-signal tray to the top-right.

What it buys: on a row whose title wraps to a second line, a centred ring and
tray drift downward with the text, so in a scanned list the rings sit at
different heights from row to row. Pinned, they form two straight columns down
the list and only the text block grows.

Unchanged at accessibility sizes: that branch is a `VStack` (Codex's
`@ScaledMetric` pass, `74680bb`), where there is no cross-axis to pin and the
ring leads the stack anyway.

### ✅ Resolved — the ledger ring prints "42% / READING", not a bare "42"

**Decision: the owner's, 2026-09-12**, overruling both spec 1d/1ad and the
reasoning recorded against them. Those artboards draw the ledger ring's figure
bare, and `WorkProgressRing.showsPercentSuffix` existed to serve that: at 44pt
the `%` glyph cost a sixth of the ring's inner width and repeated what the
ring's own fill already showed.

Two things answer that. The ring is no longer 44pt — it is the signal tray's
height (~59pt), so the glyph now costs about a ninth of a wider box. And the
Home card's ring (`HomeCards.progressRing`) has always printed both the sign
and a state word, so the ledger ring was the odd one out inside the app before
it was faithful to the artboard.

`showsPercentSuffix` is gone rather than flipped: with its one `false` caller
removed it had no non-default caller left, and a knob no surface turns is a
knob to delete. A future surface that wants a bare figure can re-add it.

The state word follows `HomeCards`' own wording — "Reading" under a part-read
work, "Finished" at 100% — with one difference forced by where it is drawn: a
ledger row draws the ring for **every** work, including ones never opened, so
`WorkRow.ledgerProgressState` returns nil at zero. "0% READING" would claim a
reading session that never happened.

### ✅ Resolved — the ledger row has no offline tick, and one line per fact

**Decision: the owner's, 2026-09-12**, in three steps on the same day: the green
"held offline" tick moved from the head of the metadata line to its trailing
edge, and then off the card entirely — *"that checkmark is not in the spec, get
rid of it."*

It is a density reduction and the gate's own wording allows it: a reduction that
is **explicitly approved** is not a regression. What goes with it is the only
at-a-glance mark that a work would open with no network. It remains visible on
Work Detail and in Library's own download state; the row's job is which work
this is and how far in you are.

`WorkLedgerRow.metadataSymbol`/`metadataSymbolTint` are gone with it rather than
left unfilled. Spec 1t (visit count) and 1aj (star) want a glyph in that slot and
can re-add the pair when one of those is built — an empty slot kept for a screen
that does not exist yet is a knob nobody turns.

**The title is one line now, not two reserved**, and the metadata line moved out
from under the card into the title's own column. Kicker, title and metadata are
three single lines there, which comes to about the ring's height — so the card is
as tall as the ring and the tray flanking it rather than a line taller, and the
uniform-height property the reserved second line was bought for is now a
property of the row having a fixed number of lines at all.

That column is narrower than the card, which is what **compacted the word count**
(`WorkStat.localWorkMetadata`): past 999 the figure prints as "1K", "1.25K",
"33.7K", "1.2M". `.compactName` is the app's existing convention for a big figure
in a small space; the two fraction digits are what keep 1,250 from rounding to
the default one digit's "1.2K". Both callers take it — the ledger row and the
Home resume hero — because the same work reading "33.7K words" on one and
"33,700 words" on the other is the kind of difference a reader notices.

### ✅ Resolved — a ledger row is not a search result, and does not expand

**Decision: the owner's, 2026-09-12.** Ledger cards are a different kind of card
from search results — one line that says which work this is and how far in you
are, in a list you scan — so they carry no disclosure at all.

This reverses `74680bb`, which widened `isExpandableWork` to
`presentation == .ledger || …`, and the reasoning recorded for it on 2026-09-10:
that the ledger row's shorter metadata line left six facts reachable only
through the disclosure, so removing it would be a density regression. That
reasoning was about *reachability*, and the answer it missed is that the facts
are one tap away on Work Detail, which is where a reader goes for them. The
density gate's own wording allows this: a reduction that is **explicitly
approved** is not a regression.

What went with it: `expandedLedgerDetails` (byline, fandoms, dates, summary,
tag groups — all of them Work Detail's content), the ledger row's expand
button, and the blurred branch's ledger clause in `MatureContent`, which would
otherwise have given a gated row a control the unblurred row no longer has.

**Three screens lost their "Expand All" menu item** — Home's section list,
Library's section list and the queue browser. Each showed it only in detailed
mode, and detailed mode is exactly where ledger rows are drawn, so after this
change the control could not have done anything. Screens that still draw
standard or remote rows keep theirs: Search, Collections, the author profile,
series detail, and the account works lists, which mix local ledger rows with
remote AO3 rows.

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

## 3c. What to do next

Phases 5, 6, 11 and 12 are now the cheap ones. `SubjectFormRow`,
`SubjectFieldLabel(.formGroup)`, `subjectPanel()`, `SubjectRowSeparator` and
`SubjectSegmentedControl` are exactly what those ~50 artboards are drawn from,
and `Scripts/redesign-spec-inventory.py --board <id>` will say which shapes any
one of them needs, ranked by how shared they are.

Two candidates, in order of value:

1. **The filter panel** (`1ao`–`1au`), which is Phase 3's remaining work and the
   form family's real proving ground. `LibraryFilterPanel` is a native `Form`
   with `.formStyle(.grouped)`, used both as an iPhone sheet and an iPad/macOS
   inspector, and Search has its own parallel panel. Deliberately **not** taken
   on in this session: rewriting a working themed `Form` into hand-built rows,
   with no local type checker and no simulator, is a large change whose failure
   mode is invisible until someone opens the sheet. Worth doing with a device.
2. **Account subsections** (`1o`–`1ac`), Phase 6. Every one opens with the same
   header — kicker · rule · 32pt title · tally line — at a **16pt** gutter
   rather than 1a's 26. `SubjectHeaderBlock` already draws it; only the gutter
   differs, which probably wants a parameter rather than a second type.

## 4. Working notes for whoever is next

### A number on an artboard is a drawing, not a source (2026-09-14)

Two of the figures drawn in the spec contradict what the app and AO3 actually
do, and both would have misled a reader if copied:

- **1bj** says Recently Deleted holds things for **30 days**. The app's window is
  **90** (`PreservedWorkService`, carried through backup schema v7). Already
  caught by whoever built that screen, and `RecentlyDeletedView` says so in a
  comment — which is how this pattern got noticed at all.
- **1x** says unposted drafts are deleted after **29 days**. otwarchive's own
  `features/works/work_drafts.feature` purges a draft created 31 days ago and
  keeps one created 29 days ago, under a scenario named "Old drafts created are
  purged after 30 days". The rule is **30**. Taking the drawn number would have
  told writers their work was safe for a day longer than it is.

So: **check every figure before drawing it.** The source is otwarchive's config
or specs for AO3's rules, and the implementing service for the app's own. Both
were a single lookup. Neither artboard is wrong about *what to say* — both are
wrong about the number, and the number is the part that matters to someone
deciding whether to act.

The related failure runs the other way, and is mine from this same run: I
dropped Subscriptions' "N with new chapters" subtitle after grepping for
`newCount`, which does not match `newChapterCount`. The figure existed the whole
time. An empty grep is a failed search, not an answer — widen it before
concluding a thing does not exist.

### The fidelity sweep, and what it is blind to (2026-09-14)

Run after the phase table twice claimed a screen was done when it was not
(Comments, then the Account hub). The check that caught both, generalised:

```sh
# hub / form / panel screens
grep -cE "SubjectHeaderBlock|subjectPanel\(|SubjectFormRow|subjectScreenWash|\
SectionRuleHeader|SubjectStatStrip|pageBodyRow|SubjectChip|SubjectFieldLabel" <file>
```

**Result: no further hub or form screen is unredesigned.** Comments and the
Account hub were the two, and both landed on 2026-09-13/14.

Three blind spots, each of which produced a false positive before it was
understood — anyone re-running this should know them:

1. **There are two vocabularies, not one.** The `Subject*` family dresses hubs,
   forms and panels; a separate card/ledger family (`cardRow`, `CoverArt`,
   `WorkStatLabel`, the ring and signal tray, `CardListMetrics`) dresses work
   rows. `Library/WorkRow.swift`, `Search/AO3WorkRow.swift` and
   `Search/SearchPaginationBar.swift` all score zero on the grep above and are
   fully redesigned — 21, 21 and 16 hits on their own family. Screening a row
   component with the form grep says nothing.
2. **A screen is often not in the folder named after it.** Artboard 1g, "Browse
   — fandom clusters", is implemented in `Features/Search/MediaBrowserView.swift`;
   `Features/Browse/` holds the works lists it pushes to. Map artboard → file
   through the status log's commit (`git show --stat <sha>`), not through the
   directory name.
3. **Zero hits in a 1,900-line file is not proof of neglect.** `CommentThreadRow`
   scores zero and is the most deliberately designed screen in the app; its model
   was chosen over three others on a device (§3b).

Spot-checked beyond the grep, and sound: **1g** draws the dashed `+N more` chip
the artboard asks for and carries `isApproximateWorkCount`, which states when a
category total is a sum of per-tag counts rather than a figure AO3 printed —
the build note's own data gap, answered honestly in a doc comment rather than
papered over.

### Two things 1a deliberately does not draw (2026-09-14)

Audited the Work Detail artboard element by element against
`Features/WorkDetail/`. Everything it draws is there — identity block, figure
strip, serif summary, ON AO3 chips, tag clusters, the grouped facts card, the
kudos/comments/bookmarks/hits tally, Mark finished, the My copy row, and on the
sheet the progress/storage strip, the status toggles, the queue rows with their
positions (`"\(queue.name) — #\(index + 1) of \(orderedWorks.count)"`), the
collections and the conversion provenance.

Two elements are drawn in the artboard and absent from the app **on purpose**.
Both would have to be invented to appear, so anyone reading the artboard and
reaching for the code should stop here first:

- **"Part 2 of 4"** on the series row. The app renders `"Part 2"`. The total is
  not on a work page — AO3 prints the position there and keeps the count on the
  series page — so the "of 4" costs a request for a fact nobody asked for, and
  guessing it is worse. `seriesFactRow` is already correct.
- **"9 pages left"** on the resume card. `ReaderPageMetrics.workRemainingPositions`
  does compute this, but only with a Readium publication open; nothing persists
  it on the work. Work Detail would have to open the book to state it. Worth
  doing only if the reader starts persisting the figure for its own reasons.

The pattern is the plan's §4 rule holding: a figure that cannot be sourced is
dropped, not approximated. Both omissions are the code being right, not behind.

### Unattended-run policy (added 2026-09-13, for the overnight loop)

The owner set a loop running while asleep, with one objective: **follow the spec
as closely as possible and get every artboard faithfully recreated.** The loop's
failure mode is not bad code — it is stopping to ask a question nobody is awake
to answer. So:

- **Decide, record, continue.** Any choice that a commit can reverse gets made,
  written down in the commit message and here, and flagged for morning review.
  Never hold work for an answer. State the alternative you did not take.
- **Never do the irreversible.** No push, no merge to `main`, no release, no
  `git reset --hard`, no deleting a branch or a worktree, no AO3 write against a
  live session. Those wait for the owner, however obvious they look at 3am.
- **The artboard is the source of truth for what a screen should look like; the
  running code is the source of truth for what it does.** Where the spec
  contradicts a decision that was already settled *with evidence* — a device
  comparison, a measured figure — keep the code and file the conflict in §3b as
  open. Where it contradicts mere reasoning, the artboard wins (§3b's own rule).
- **Verify the claim, not the checkbox.** This table has now twice said a screen
  was done when it was not: Comments (§Phase 7) and the Account hub (§Phase 5),
  both caught by the owner rather than by the plan. Before building, grep the
  screen for the design-system primitives (`SubjectHeaderBlock`, `subjectPanel`,
  `SubjectFormRow`, `subjectScreenWash`, `SectionRuleHeader`). A screen that
  uses none of them has not been redesigned, whatever the row says.
- **Definition of done per screen:** iOS Simulator build, macOS Debug build,
  `Scripts/lint.sh` exit 0, the focused tests for anything with logic in it, a
  commit, and a row here. A screen that has not been built on both platforms is
  not done.
- **Figures must be sourced or dropped.** If the spec draws a number the data
  cannot support, do not invent it and do not dress a loaded-page count as a
  site total — drop the cell or say what it counts, as the Comments signal strip
  does.

**Decisions taken under this policy, for morning review:**

- **1y Dashboard's performance strip is the signed-in user's own profile only.**
  `AO3DashboardView` is a 30-line wrapper around `AuthorProfileView`, so
  anything added there lands on *every* author's profile. The artboard says
  "**your own** works with their performance", and surfacing a stranger's
  per-work kudos/comments/hits/bookmarks is a product decision the spec does not
  make. Gated rather than global; flip the gate if the owner wants it everywhere.

## 4a. Standing notes

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
  does not have (a local reading log — meaning a *history* of sessions, which
  really is absent; the current position is stored, see `74680bb`), per-queue
  completion state, featured
  fandoms per category, AO3 write endpoints). Those are separate engineering
  tasks; the redesign should not fake them. Where a screen cannot be honest,
  build the layout and leave the data path as an explicit `TODO` with the
  artboard id in it.
- The canvas can be re-read without the 2 MB file: `dv-opt` blocks carry the
  artboard id, `data-screen-label` names each screen, and `dv-build` notes say
  what AO3 does and does not allow. Extracting each screen to its own file and
  printing an indented outline of tags + inline styles is how the tokens in §1
  were measured.

### pickers-built-2026-09-15

The owner's answer to the dead-chevron question was "build the pickers".
Eighteen rows drew a disclosure chevron and pushed nowhere. Closed as:

**Built (18 rows across 3 screens).**

*Edit Multiple Works (1bn), 8.* Archive warnings and Categories are
three-state add/remove, reusing Search's `FilterSelectionState` cycle and
its include/exclude colour roles. Remove from collections reuses
`WritingTagsRow` with `kind: nil`, which already renders a multi-select
over options. Add to collections is free text, because AO3's field is
`work[collections_to_add]`, a comma-separated input — a picker over
`currentCollections` would have offered the *remove* list. Who can comment
is now parsed: `parseBulkEditForm` reads `work[comment_permissions]` with
the same `parseRadios` helper the single-work form uses. Add co-creators is
a text field. Remove co-creators was relabelled **Remove me as a
co-creator** and rebuilt as a toggle — AO3's field is `remove_me`, one
checkbox taking *you* off the works, never a list of people.

*Work Edit (1bo/1bs), 5.* The item recorded three; there were five. Work
skin and Who can comment were one `WritingChoiceRow` each — `parseWorkForm`
had populated `workSkinOptions` and `commentPermissionOptions` all along
and nothing read them. Co-creators got a screen combining the pseud
multi-select with the co-author byline (both parsed by `parseCreators`,
neither previously editable). Inspired by got a screen for AO3's
`parent_attributes` group. Chapters posted follows 1bo's own footnote: the
posted count is AO3's to report, the total is the writer's to set.

*Edit tags (1bq), 5.* Rating plus the four tag rows, straight reuse of
`WritingChoiceRow` / `WritingTagsRow`.

**Not built, and why.**

*Gift recipients (1bn).* otwarchive's `edit_multiple` carries no gift field
at all. 1bn draws the row so it stays, disabled and reading "Per work"
rather than a chevron into nothing.

*Twelve read-only rows.* `ChallengeSettingsView` is read-only by its own
doc comment; `TagSetView`'s nomination limits and `ModeratedItemsView`'s
tallies are the same. AO3 has no native edit for them. The chevron was
removed; the rows and their values stay.

*One row deleted.* "Minimum words: 5,000" was a hardcoded string with no
model behind it — the artboard's mock figure shipped as fact.

**Method note.** The repo's `ao3_edit_multiple.html` fixture is hand-written
and lacks fields the real page has, so its silence is not evidence; three
answers here came from reading otwarchive's own `edit_multiple.html.erb`
and `_work_form_pseuds.html.erb`. The fixture now carries the
`comment_permissions` radios and `remove_me` checkbox, with a test pinning
the rule that matters most: **a field the reader did not touch must not
appear in the POST**, or a bulk save overwrites it on every selected work.

**Detector note.** A naive `showsDisclosure: true` vs `subjectRowNavigation`
count reads 30 dead where the truth was 15. `SubjectFormRow`'s convenience
init takes `action:` **last**, so a trailing closure binds to it; rows using
`.onTapGesture` are live too. Count a row dead only if it has no `action:`,
no `.subjectRowNavigation`, and no trailing action closure.

Repo-wide check is clean: every chevron now has somewhere to go.
