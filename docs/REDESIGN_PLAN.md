# Kudos redesign — plan, status, and handoff

**Branch:** `codex/kudos-redesign` · **Task row:** `T-212` in [`TASKS.md`](../TASKS.md)

Source of truth is the owner-supplied **Final Redesign Spec** design canvas
(`Final_Redesign_Spec.dc.html`, local-only — 87 artboards / 104 screens). This
file is the *durable* record of what it says and how far the implementation has
got, so a session that runs out of context can be replaced by a fresh one with
zero archaeology.

---

## 0. Environment constraint — read this first

**This branch has been worked on from a Linux container with no Swift
toolchain.** `xcodebuild`, `swift`, `swiftlint` and `swiftformat` are all
absent, so `Scripts/verify.sh` (and every gate inside it) **has not been run**
on the redesign commits.

Consequences, stated plainly:

- No commit on this branch has been compiled. Syntax and type errors are
  possible. Everything has been written conservatively (no clever generics, no
  new concurrency, no `any`/existential tricks) to keep that risk low, and each
  new file is self-contained enough to fix in isolation.
- The human screenshot gate in `AGENTS.md` has not been satisfied for any of it.
- **First thing a macOS-capable agent should do on picking this up:** build the
  iOS target, fix whatever the compiler finds, and commit that as its own
  "make the redesign branch compile" commit before adding screens.

Nothing here should be merged toward `merge-test` until that has happened.

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
| **1** | Home tab — `1b`, then `1ad`, `1ae`, `1af`, `1ag` | ⬜ next |
| **2** | Library tab — `1c` (shelves), `1d` (ledger) | ⬜ |
| **3** | Search — results `1k`, filter panel `1ao`–`1au`, tag picker `1av`–`1aw`, save `1ax` | 🟡 row done, screen not |
| **4** | Browse — `1g`, `1al`, `1am`, `1an` | ⬜ |
| **5** | Account — hub `1m`, signed out `1n`, scopes `1bt` | ⬜ |
| **6** | Account subsections in hub order — `1o`, `1q`, `1t`, `1p`, `1r`, `1s`, `1u`, `1v`, `1w`, `1x`, `1l`, `1y`, `1z`, `1ab`, `1ac`, `1aa` | ⬜ |
| **7** | Work detail `1a`; Comments `1f`, `1ba`, `1be`, `1bf` | ⬜ |
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
| `9ee86ba` | Claude | `SubjectSurface.swift`; collapse onto one palette | unreviewed | Wants a non-Claude reviewer. Never compiled — see §0. |
| `5a0a804` | Claude | Unsigned-IPA script + CI workflow; review ledger | unreviewed | Shell syntax checked (`sh -n`); `xcodebuild` path unrun. |

**Family names to use:** `Claude`, `Codex`, `Grok`, `Gemini`, `Human`.
Version numbers are welcome in Notes but the family is what gates rule 1.

---

## 3. Status log

Newest first. Each entry: what landed, what it was verified against, what is
left. Keep appending — this is the handoff channel.

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

---

## 4. Working notes for whoever is next

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
