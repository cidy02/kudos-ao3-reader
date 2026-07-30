# Reader Redesign — Report & Handoff

**Audience:** a stronger LLM (or human) polishing branch `from-keen-cori-d0a989`  
**Author session:** Grok (xAI), multi-agent adversarial review pipeline  
**Date:** 2026-07-27  
**Stance:** ship-quality handoff for a **critical** product surface. Prefer correctness and must-not-regress rails over new features.

---

## 0. How to use this document

1. Read **§1 Scope & branch state** before any edit.  
2. Treat **§2 Must-not-regress** as hard law (with AGENTS.md / DATA_AND_PERSISTENCE / AO3_NETWORKING).  
3. Use **§4 Open issues** as the work queue. Each issue includes a **2/3-validated fix** (or explicit “needs re-spec”).  
4. Use **§5 Recommended polish order** as the default DAG.  
5. Do **not** commit temporary A/B identity (`Kudos-NewReader`).  

**Review method used here**

| Pass | What | Gate |
|------|------|------|
| Area reviews | 4 independent deep-dives (Chrome/PageBar, TTS, Annotations/Search/Backup, Architecture) | Findings inventory |
| Fix validation | 3 validators per cluster (Chrome, TTS, ANN, Arch) | **≥2/3 ACCEPT** required to recommend a fix |
| Page-bar snap | Dedicated 5-agent rounds (r1 fail → r2 4/5 → r3 residual fix → **r3 5/5 PASS**) | Supermajority 4/5 for that bug class |

Where validators disagreed, this doc records the **consensus fix** and constraints. Where issue IDs drifted between agents, the **canonical IDs** below are authoritative.

---

## 1. Scope & branch state

### 1.1 What this branch is

| Layer | Content |
|-------|---------|
| Base | `claude/keen-cori-d0a989` @ ~`9402456` (HIG stack) |
| Committed reader redesign | `865e7a6` T-148 chrome “4a” · `40194a6` menu morph / paged layout / annotation model · `1e06d3b` whole-line page-box snap · `33349be` backup manifest **v8** annotations |
| **Uncommitted WIP (large)** | TTS / Now Playing / mini-player chrome, highlights host + colour bar, search, orientation lock, **page-bar dual-metric state machine**, dismiss peel hardening, A/B pbxproj identity |

The redesign **far exceeds** original T-148 (“chrome only”). Treat the dirty tree as a **feature branch**, not chrome polish.

### 1.2 Platform

- **iOS / iPadOS only** for redesign + Readium (`#if os(iOS)`).  
- **macOS** still uses legacy WKWebView reader (`BookReaderView` router).  
- Readium SPM products: `platformFilter = ios`.  
- **Never “unify” platforms** or delete macOS reader paths in this polish.

### 1.3 Working tree hygiene (critical)

| Item | Status |
|------|--------|
| `PRODUCT_BUNDLE_IDENTIFIER = com.cidy02.Kudos.NewReader` | Local A/B only — **must not commit** |
| Display / product name `Kudos-NewReader` | Same |
| `PRODUCT_MODULE_NAME = Kudos` | Keep for `@testable import Kudos` while product name differs; drop when product returns to `Kudos` |
| `TEST_HOST` still `Kudos.app` while product is NewReader | Scaffolding inconsistency — realign on revert |
| Cosmetic pbxproj churn | Revert before stage (`git checkout -- …/project.pbxproj` if unintentional) |
| New Swift under `kudos-ao3-reader/` / `KudosTests/` | Auto-included by synchronized groups — **do not edit pbxproj to add files** |

### 1.4 File inventory (reader redesign)

**Committed chrome helpers**

- `ReaderChromeTopBar.swift`, `ReaderFanMenu.swift`, `ReaderPositionCard.swift`, `ReaderContentsSheet.swift`, `ReaderTimeEstimate.swift`

**Untracked / new (WIP)**

- TTS: `ReaderSpeechController.swift`, `ReaderSpeechPreferences.swift`, `ReaderSpeechSettingsSection.swift`, `ReaderSpeechSkip.swift`  
- Metrics: `ReaderPageMetrics.swift`, `ReaderChapterScrub.swift`  
- Annotations: `ReaderHighlightHost.swift`, `ReaderNoteEditor.swift`, `ReadingAnnotationColorPicker.swift`, `ReadingAnnotationMatching.swift`  
- Search: `ReaderSearchView.swift`  
- App: `ReaderOrientationLock.swift`  
- Tests: `ReaderPageMetricsTests`, `ReaderChapterScrubTests`, `ReaderSpeechPreferencesTests`, `ReaderSpeechSkipTests`, `ReadingAnnotationMatchingTests` (+ committed backup tests)

**Monolith**

- `ReadiumReaderView.swift` ≈ **3100+ lines** — `BookReaderView`, style mapper, `ReadiumBook`, dismiss peel UIKit, navigator host, full SwiftUI chrome/TTS/annotation orchestration.

### 1.5 Prior session audit (partially stale)

`docs/audits/SESSION_REVIEW_reader_tts_highlights_2026-07-27.md` is valuable history but **lags the code** on several items already mitigated:

| Session finding | Current tree (2026-07-27 later) |
|-----------------|----------------------------------|
| P0 mini-player dies with chrome | **Mitigated** — decoupled standalone mini when chrome down + `speech.isSessionActive` |
| Dual AVAudioSession | **Mitigated** — controller documents Readium-only ownership; no app `setActive` |
| `prepare()` always tearDown | **Mitigated** — same `ObjectIdentifier(publication)` + live synth → no-op |
| Highlight text+position false positive | **Mitigated** — locator-string equality only |
| Colour bar magic `+88` / no dismiss | **Mitigated** — bottom `VStack` + dismiss token / chrome hide |

**Do not re-implement those mitigations.** Do re-verify on device.

---

## 2. Must-not-regress (polish LLM hard rails)

If a change conflicts with these, **stop** and re-read the cited docs.

1. **Progress write policy** — mid-scroll uses debounced locator writes only; full `markProgressModified` on open / flush / true completion — not every tick (`ReadiumProgressPersistence`, DATA_AND_PERSISTENCE).  
2. **Flush points** — dismiss, disappear, scene background; force-quit loss ≤ debounce window.  
3. **Completion** — `ReadiumReaderCompletion.isAtEnd`: final reading-order resource visible **and** progression upper bound **exactly 1.0**. Never reintroduce `totalProgression >= 0.99`.  
4. **Page bar scale purity** — “Page X of Y” is **swipe-scale only** (`visualPage` / `visualPageCount` / `pageBarReady`). Never paint Readium ~1KB positions as that label.  
5. **Page bar thrash architecture** (see §3.1) — dual-agree first publish; JS never first-publishes; majority primary webview; no progression digit reseeds after ready; no proportional digit rescale on count growth.  
6. **Dismiss peel** — freeze + exit latch block locator/visual/completion ingestion; pre-exit progress flush; no late settle corruption.  
7. **Annotations** — delete inserts `.readingAnnotation` tombstone then hard-delete; backup v8 round-trip; no resurrect from older archive.  
8. **TTS lifetime** — leave work → `tearDown` (stop + remotes + NP); no Personal Voice; hold-seek uses `ReaderPageMetrics`, not raw `page - 1`.  
9. **Chrome hit-testing** — hidden chrome not invisibly tappable; speech-active transport remains hittable when chrome hidden.  
10. **AO3 networking** — kudos/comments stay on existing auth write paths; no new UA / raw URLSession (AO3_NETWORKING_POLICY).  
11. **macOS** — legacy reader + dual-platform builds stay green.  
12. **pbxproj** — no NewReader identity on shared branches; no file-add edits for synced groups.  
13. **Module** — `@testable import Kudos` must keep working.

---

## 3. What has landed (strengths)

### 3.1 Page bar — dual metric state machine (major session work)

**Problem class solved:** mixing position-list scale (“2 of 13”) with swipe scale (“6 of 103”); open thrash; next/back digit snap.

**Architecture (keep intact)**

| Mechanism | Role |
|-----------|------|
| `pageBarReady` / `visualPage` / `visualPageCount` | Atomic swipe-scale metrics |
| `clearVisualPageMetrics` | Chapter/open: gen bump, hide bar, **2.0s** user-scroll mute, cancel digit refresh |
| `schedulePageBarRemeasure` | **Absolute** delays 0.5 / 1.0 / 1.6s (not sequential stack ~3.1s) |
| Primary WKWebView | Single most-visible sample with **≥55%** root area |
| Dual-agree | Two matching layout counts before first unmask (final-alone still residual — C4) |
| Layout JS | Returns **pageCount + scroll-derived page** same sample |
| First digit | Prefers `measuredPage`, progression only as rare fallback |
| `applyVisualPageFromUserScroll` | Requires ready + `pageCount == known`; **never first-publishes** |
| JS inject | Debounce settle (140ms), not throttle-first mid-animation |
| `scheduleSettledPageDigitRefresh` | Same-resource edge-tap/goForward: 220ms debounce, `digitOnly`, count match |
| UI | `!pageBarReady` → card page 0 → visual **“Page …”**; slider sync no-op until ready |
| `readingPosition` | Prefers live `visualPage` once ready |

**Adversarial gate (snap issue only):** round 3 → **5/5 PASS** (wrong-then-right progression/neighbor class substantially closed). Residual risks listed under C3–C8.

### 3.2 Chrome “4a”

Floating Liquid Glass layers: top bar (close + title/author), fan menu (morph pills + rounds), position card (page + scrub + work line). Content-sized hit testing; fan backdrop dismiss; AO3 place honesty (Preface/Summary/Afterword via `ReaderPositionSummary.Place`).

### 3.3 Dismiss

UIKit full-card bitmap peel (`ReaderDismissDragSurface`); lock transform; locator ingestion blocked during freeze + exit latch.

### 3.4 Page box (committed)

`navigatorContentInset`: window `safeTop` + `snappedBottomInset` (whole-line remainder + min 8pt). Unit-testable pure math. Residual **padding perception** is the **C2** hybrid with chrome/safeAreaRegions — not the snap math alone.

### 3.5 TTS

- Readium `PublicationSpeechSynthesizer` + rate/pitch bridge  
- Mini player in card when chrome up; **standalone** when chrome down + session active  
- Fan waveform = full stop (pause on mini) — intentional  
- Now Playing + remotes; background audio mode inject for A/B  
- Hold-seek / skip pure helpers + tests  

### 3.6 Annotations + backup v8

- SwiftData `ReadingAnnotation`; locator-only same-passage match  
- Colour bar in bottom VStack; dismiss on chrome/context/position  
- Contents Bookmarks / Notes (naming lag — ANN-4)  
- Manifest v8 export/import + tombstone suppress tests  

### 3.7 Search

Debounced Find in Work; serial iterator paging (concurrency-safe). Residual: failure freezes paging (SRC-1).

---

## 4. Open issues & 2/3-validated fixes

### Severity legend

- **P0** — process/data/user-facing ship blocker  
- **P1** — real bug or clear UX/data footgun  
- **P2** — polish / edge / maintainability  

### Validation legend

- **2/3+ ACCEPT** → recommended for polish LLM  
- **2/3 ACCEPT with constraints** → implement only under listed constraints  
- **Needs re-spec** → do not implement the original one-liner; use the consensus policy  

---

### 4.1 Chrome / page bar / layout

#### C1 — P1 — VoiceOver “Page 0 of 1” while measuring  
**Evidence:** Visual uses `page < 1` → “Page …”; `pageAccessibilityLabel` still `"Page \(page) of \(max(1, pageCount))"`.  
**Fix (3/3 ACCEPT):** When `page < 1 || pageCount < 1`, a11y = `"Measuring pages"` / `"Page …"`; share one helper with visual title.  
**Tests:** pure string helper.

#### C2 — P1 — Excessive top/bottom padding / triple geometry model  
**Evidence:** Peel host `safeAreaRegions = []`; chrome pads fixed 8/12; content inset top = **live window safeTop**; navigator ignores safe area. Owner-reported airy top/bottom.  
**Fix (2/3 ACCEPT, constrained):**  
1. Pick **one static** geometry model:  
   - **Preferred:** full-bleed host + **window** safe area is the single source; chrome insets = `safeArea + chromeInset`; content top either 0 or the **minimum** needed so text clears system chrome **without** double-counting host auto-inset.  
   - Bottom: keep whole-line snap; do not fold floating card height into page box unless product redesigns immersion.  
2. Device-measure host bounds, chrome frames, safe insets chrome up/down.  
3. **Must not** couple content inset to `chromeVisible` (that is thrash — C6).  
**Agent note:** one validator REJECT’d naive “content top = 0” without frozen metrics; implement C2 + C6 together.

#### C3 — P1 — Vertical `pageCount` never shrinks after ready  
**Evidence:** hard return when ready + vertical + smaller count; inflated Y sticks.  
**Fix (3/3 ACCEPT):** Allow vertical shrink only after **≥2 agreeing smaller** layout samples (reuse dual-agree machinery), never one-shot; keep majority primary filter.

#### C4 — P1 — Final remeasure can first-publish alone  
**Evidence:** `pendingLayoutAgrees < 2 && !isFinalAttempt` → final 1.6s can unmask unconfirmed count.  
**Fix (3/3 ACCEPT, constrained):** Hold **“Page …”** until dual-agree even on final. **No provisional numeric** Page X of Y. Prefer more ticks / event-driven remeasure over escape hatch.

#### C6 — P2 — Chrome toggle changes status bar / safe area without page-bar policy  
**Evidence:** `.statusBarHidden(!chromeVisible)`; content inset reads live window safeTop; no freeze/remeasure on chrome flip.  
**Fix (consensus):** **Freeze** page-box safe metrics across chrome show/hide. **REJECT** clear+remeasure on every chrome tap (reopens open-bar thrash). Remeasure only if real geometry delta (rotation, prefs, resource turn).

#### C5 / C7 / C8 / C9 / C10 — P2 residuals (documented, lower priority)

| ID | Issue | Suggested fix (not fully 2/3-gated) |
|----|-------|-------------------------------------|
| C5 | `pageCount==1` reject only if hint > 3 | Tighten threshold for multi-position chapters |
| C7 | digitOnly no-ops on count mismatch | Schedule full remeasure, not silent return |
| C8 | `round(x/vw)` ±1 at boundaries | Shared pure page index + hysteresis tests |
| C9 | Bottom chrome vs home indicator | Folds into C2 |
| C10 | Stub `ReadingPosition` 1/1 when !ready | Optionals or gate `pageLabel` |

---

### 4.2 Page-bar snap (status)

| Field | Value |
|-------|-------|
| Status | **CLOSED for thrash class** — r3 **5/5 PASS** |
| Landed | Absolute remeasure schedule, 2s mute, JS never first-publish, majority 55%, measuredPage first digit, digitOnly settle refresh, slider freeze until ready |
| Residual | Final-alone (C4), sticky vertical count (C3), ±1 round (C8), brief settle lag — polish under C* not a re-open of position-list thrash |
| Device | **Still required** — next/back same chapter + chapter boundary + open resume |

---

### 4.3 TTS

#### T1 — P1 — Fan treats `.unavailable` as active  
**Evidence:** Fan / `toggleReadingAloud` use `status != .stopped`; bottom chrome correctly uses `isSessionActive`.  
**Fix (2/3+ ACCEPT):** Use `speech.isSessionActive` for emphasize, a11y label, stop branch; keep `isEnabled: speech.isAvailable`.

#### T2 — P1 — Remotes survive mini-player stop  
**Evidence:** `stop()` clears NP only; `removeRemoteCommands()` only in `tearDown`.  
**Fix (needs re-spec → 2/3 on policy):**  
**Session-end policy (ACCEPT this package, not “stop() only”):**  
- On explicit stop **and** synthesizer `.stopped`: clear NP **and** remove remotes.  
- Reinstall remotes only on next explicit start.  
- Update ARCHITECTURE_MAP (today documents stop-without-remotes).  
- Do not leave ghost RCC handlers after strip dismiss.

#### T3 — P1 — Private Settings deep links  
**Evidence:** `SystemSpokenContentSettings` only `App-prefs:` / `prefs:`.  
**Fix (2/3 ACCEPT, constrained):** Best-effort private candidates OK; **public** fallback = Apple support article for Spoken Content / download voices + honest footer (“you may need Accessibility → Spoken Content → Voices”). **Do not** claim `UIApplication.openSettingsURLString` opens Spoken Content (it opens **this app’s** settings).

#### T4 — P2 — Now Playing duration is silent-reading model  
**Evidence:** `secondsPerPosition = 55` silent WPM → NP duration; rate ignored.  
**Fix (2/3 for honesty path):** Prefer **omit** duration/elapsed (`nil`) until a speech-paced model exists. Do **not** claim silent-read × rate is “TTS duration.” Leave position-card silent estimates alone.

#### Already mitigated (verify only; do not re-build)

- Mini-player chrome decouple  
- Readium audio session ownership  
- `prepare()` same-publication no-op  
- Fan = stop (product intentional given mini pause)

---

### 4.4 Annotations / search / backup

#### ANN-1 — Locator-only matching  
**Status:** **Landed.** Keep exact locator equality. **Do not** reintroduce text+position fallbacks. Residual stacks from non-identical overlapping ranges are accepted tradeoff (optional future CFI overlap — separate task).

#### ANN-7 — P1 — Restore LWW does not re-home `work`  
**Evidence:** LWW branch copies fields, never `local.work = work`.  
**Fix (2/3+ ACCEPT):** On LWW apply set `local.work = work`. Unit test re-home. Optional: re-home when `local.work == nil` even if content LWW loses.

#### ANN-8 — P1 — Multi-device same passage, two UUIDs  
**Evidence:** Merge by record id only.  
**Fix (2/3 ACCEPT, constrained):** On restore/sync, for same work + kind + **exact locator string**, keep winner by `lastModifiedAt`, **tombstone + delete** loser. Salvage non-empty note onto winner if needed. Same-kind only. Never fuzzy text match.

#### ANN-9 — P1 — `WorkLifecycle.hardDelete` orphans annotations  
**Evidence:** Tombstones work + queue memberships only; annotations have no cascade.  
**Fix (2/3+ ACCEPT):** Before deleting work: for each annotation, insert `.readingAnnotation` tombstone then delete (mirror memberships). Soft-delete must **not** destroy marks. Test: hardDelete → zero annotations + tombstones.

#### ANN-2 (product P2) — Second Highlight always deletes  
**Split validators:** recolor-if-`lastUsed` differs vs keep Apple-ish toggle-off.  
**Recommendation:** **Do not change default without product OK.** Prefer colour bar + editor for recolor. If product wants: same colour → delete; different lastUsed → recolor + `markModified` (no tombstone).

#### ANN-4 — P2 — Segment titled “Notes” lists all highlights  
**Fix (2/3 ACCEPT):** Rename segment to **Highlights** (case rename free). Optional fan “Bookmarks & Highlights.”

#### SRC-1 / SRC-2 — P2 search  
- Failure sets `reachedEnd` → truncated results: leave retryable, don’t poison.  
- Jump has no match paint: temporary decoration if available.

#### DOC-1 — Matrix still “v7”  
Update REGRESSION_TEST_MATRIX to **v8 + annotations** + point at `ReadingAnnotationBackupTests`.

---

### 4.5 Architecture / process

#### A1 — P0 process — A/B pbxproj identity  
**Fix (3/3 ACCEPT):** Never commit NewReader identity. Revert before any shared push/PR. Align TEST_HOST.  

#### A2 — P1 — Title pill WorkDetail stack  
**Status:** **Mostly mitigated** — sheet + nested `NavigationStack` (not push).  
**Residual P2:** sheet `WorkDetailView` can still open **Reader₂** over live Reader₁.  
**Fix (2/3 ACCEPT residual):** From-reader detail = metadata-only (no nested open-reader), or Open dismisses sheet / no-ops. Fix stale `@State` comment that still says “pushed.”

#### A4 — P1/P2 — `ReadiumReaderView` god file  
**Fix (3/3 ACCEPT-with-scope / REJECT mega-blob):** Phased pure extract only after behavior freezes for that seam. Suggested order: `ReadiumReaderStyleMapper` → `ReadiumBook` → chrome host; peel/navigator **last**. **Zero behavior change** per extract commit. Do **not** block P0/P1 behavior on extract.

---

## 5. Recommended polish order (DAG)

```text
[0] A1 continuous — never stage NewReader pbxproj
[1] Device re-verify page bar (open, next/back chapter, same-chapter, scrub)
[2] Device re-verify TTS chrome decouple + stop/NP + fan isSessionActive (T1)
[3] C1 a11y string (cheap, isolated)
[4] C2+C6 geometry (padding) — static model + freeze on chrome toggle
[5] C4 dual-agree-only first publish; then C3 dual-agree vertical shrink
[6] T2 session-end remotes policy + ARCHITECTURE_MAP
[7] T3 prefs honesty + support article
[8] ANN-9 hardDelete cascade tombstones; ANN-7 work re-home; ANN-8 multi-device dedup
[9] ANN-4 rename Highlights; DOC-1 matrix; stale session audit update
[10] T4 NP omit duration (if touching NP)
[11] A2 residual nested-reader; A4 pure extract only when quiet
[12] Human UI density/screenshot gate before merge-test
[13] Scripts/verify.sh full green (iOS + macOS) after identity revert
```

**Do not parallelize:** C2 geometry + page-bar state machine refactors in the same commit; A4 extract + TTS/highlight behavior in the same commit.

---

## 6. Verification gates

| Gate | Status / requirement |
|------|----------------------|
| Page-bar snap adversarial | **5/5 PASS** (code review); **device smoke still open** |
| Open page bar thrash | Architecturally closed (C3/C4 now also closed); device smoke open |
| Padding (C2) | **Confirmed already correct in code** (T-150) — device perception check still open |
| TTS chrome decouple | Code present; device checklist open (`human_must_verify.md`) |
| Full `Scripts/verify.sh` on this dirty WIP | **T-150: invariants / iOS suite (724+ tests) / macOS build / whitespace all green.** Lint has 3 pre-existing hard errors, all A4 debt in `ReadiumReaderView.swift` (file/type-body length, one large tuple) — not introduced this pass, not fixed either (A4 is explicitly phased). macOS build was actually broken by the WIP (`Color(.systemBackground)`, `.toolbar(.hidden, for: .navigationBar)` used unguarded) and is fixed now. |
| Human UI density gate | Open for redesign |
| Live AO3 kudos from reader | Always owner-manual |
| pbxproj identity | Clean as of T-150 (reverted before this session began) — still block merge if it ever reappears |

### Manual device checklist (minimum)

**Page bar**

- [ ] Open mid-chapter work → “Page …” then correct swipe-scale X of Y (not 2 of 13)  
- [ ] Chapter next/back → no wrong-then-right digit; slider doesn’t jump to 0 mid-measure  
- [ ] Same-chapter page turn (swipe + edge) → digit settles once  
- [ ] Scrub seek matches visual pages  

**Layout**

- [ ] Top/bottom dead band not double-stacked (Dynamic Island + first line; last line + home indicator)  
- [ ] Chrome hide/show does not thrash page count  

**TTS**

- [ ] Fan start → mini in card; hide chrome → standalone mini; show chrome → recouple  
- [ ] Fan while `.unavailable` does **not** look “active” (after T1)  
- [ ] Stop clears strip + does not leave ghost remotes (after T2)  

**Annotations**

- [ ] Highlight / recolor / delete / list / backup restore  
- [ ] After hardDelete work (dev test) no orphan annotations (after ANN-9)  

**Dismiss**

- [ ] Swipe-down peel: no bounce; progress resume correct  

---

## 7. Tests present vs missing

**Present (keep green)**

- `ReaderPageMetricsTests`, `ReaderChapterScrubTests`, `ReaderTimeEstimateTests`  
- `ReaderSpeechPreferencesTests`, `ReaderSpeechSkipTests`  
- `ReadingAnnotationMatchingTests`, `ReadingAnnotationBackupTests`  
- `ReadiumProgressPersistenceTests`, completion/style suites  

**Missing / high value to add**

- Page-bar state machine pure extract (dual-agree, final-alone forbidden, vertical shrink dual-agree, a11y measuring string)  
- ANN-7 re-home, ANN-9 hardDelete cascade, ANN-8 locator dedup  
- `isSessionActive` call-site consistency (if extracted)  
- No UI tests required for gate; device matrix is the chrome/TTS truth  

---

## 8. Commit / split guidance

Suggested commit themes (after A1 identity clean):

1. Page-bar thrash + snap state machine (metrics only)  
2. Padding / safe-area single model (C2+C6)  
3. TTS session polish (T1+T2+docs)  
4. Annotation persistence holes (ANN-9/7/8)  
5. IA / a11y (C1, ANN-4, DOC)  
6. Optional pure extract (A4)  

**Never** mix NewReader pbxproj into any of the above.

---

## 9. Task board notes

- **T-148** still open in TASKS as chrome redesign with follow-ons (e)(f)(g)(h) partially implemented uncommitted.  
- **T-149** pure metrics helpers — largely landed and wired; update status when green.  
- Claim a new T-xx for “Reader redesign polish / residual closure” before editing; one owner.  
- Adversarial review template before stacking onto `merge-test`.  
- **Never commit to `main`.**  

---

## 10. Quick reference — consensus scoreboard

**Updated by T-150 (Claude Sonnet 5, 2026-07-28).** Everything below marked
**Closed** was implemented and either unit-tested or is a code-level
correctness argument (page-bar/geometry timing isn't unit-testable — those
need device smoke, tracked in `human_must_verify.md`). Full test suite +
macOS build + whitespace gate all green; `Scripts/lint.sh` has exactly 3
pre-existing hard errors, all in `ReadiumReaderView.swift`, all attributable
to A4 debt that predates this pass (see A4 row and `human_must_verify.md`).

| ID | Sev | Status | Fix gate |
|----|-----|--------|----------|
| Snap thrash | P0/P1 | Closed (5/5) | Device smoke still open |
| C1 a11y 0 of 1 | P1 | **Closed** (earlier session) | Kept |
| C2 padding geometry | P1 | **Closed** — already correct in code: single frozen safe-area source (`frozenPageBoxSafeTop`/`Bottom`), never coupled to `chromeVisible` | Device smoke (perception) |
| C3 vertical shrink | P1 | **Closed** — `pendingVerticalShrinkCount`/`Agrees`, dual-agree required, never one-shot | Kept |
| C4 final-alone publish | P1 | **Closed** — dual-agree gate is unconditional now; `scheduleRemeasureTicks` extends into bounded slower-cadence retries instead of an escape hatch on the last fixed tick | Device smoke (watch for a bar stuck on "Page …" — see `human_must_verify.md`) |
| C6 chrome safe freeze | P2 | **Closed** — confirmed `.onChange(of: chromeVisible)` only clears fan/colour-bar state, never triggers geometry remeasure | Kept |
| T1 fan isSessionActive | P1 | **Closed** (earlier session) | Kept |
| T2 remotes session end | P1 | **Closed** (earlier session) — verified against full re-spec: explicit stop clears NP + removes remotes, reinstall only on next explicit start/active reanchor; `ARCHITECTURE_MAP` reworded to say so explicitly | Kept |
| T3 prefs honesty | P1 | **Closed** — public `https://` candidate appended after private deep links; footer no longer promises a guaranteed jump; button relabeled "Open Settings for More Voices" | Kept |
| T4 NP duration | P2 | **Closed** — omitted (`nil`/`nil`); `nowPlayingTiming` helper kept (tested) for a future real speech-paced model, just not wired to NP today | Kept |
| ANN-1 matching | P1 | Done | Keep |
| ANN-7 work re-home | P1 | **Closed** (earlier session) | Kept |
| ANN-8 multi-device dedup | P1 | **Closed** — `KudosBackupService.dedupeSamePassageAnnotations`: same work+kind+exact-locator, newest `lastModifiedAt` wins, tombstoned loser, note salvage; 2 new tests in `ReadingAnnotationBackupTests` | Multi-device end-to-end still needs real hardware (`human_must_verify.md`) |
| ANN-9 hardDelete cascade | P1 | **Closed** (earlier session) | Kept |
| ANN-4 rename Highlights | P2 | **Closed** (earlier session) | Kept |
| A1 pbxproj A/B | P0 | Clean — reverted to `com.cidy02.Kudos`/"Kudos" before this session began | **Still never commit if it reappears** |
| A2 title detail | P1 | **Closed** — `WorkDetailView(openedFromReader:)` dismisses the sheet instead of pushing a nested reader; stale "pushed" comment fixed | Kept |
| A4 extract monolith | P2 | **Phase 1 done** — `ReadiumReaderStyleMapper` (pure, self-contained enum) moved to its own file, mechanical zero-behavior-change move, build+test+macOS-build all green. File is 2,365 lines (was 2,430); still 3 hard lint errors, all now in `ReadiumBook`/`ReadiumReaderView` itself. Stopped there deliberately: `ReadiumBook` is deeply interdependent with the page-bar/TTS/annotation state this pass just hardened — real risk, not a mechanical move. Deserves its own session. | **Phased only** |

---

## 11. Bottom line for the polish LLM

This branch is a **high-value, high-risk** reader redesign: chrome, dual-scale page bar, dismiss peel, TTS, annotations v8, and search all coexist in a dirty tree and a ~3k-line host file.

**Already hard-won (do not re-break):** page-bar thrash architecture, locator-only matching, TTS chrome decouple, Readium audio ownership, prepare identity guard, annotation tombstones on in-reader delete, completion exact 1.0, progress debounce.

**Highest remaining value:**

1. **Never commit A/B identity**  
2. **Device-prove** page bar + TTS chrome  
3. **C2 padding** (owner-visible) under thrash-safe freeze (C6)  
4. **C4/C3** finish open-count correctness  
5. **ANN-9/7/8** data-safety for multi-device / hard-delete  
6. Cheap a11y/IA (C1, ANN-4)  
7. Extract only when quiet  

Prefer **small, reviewable commits** with dual-platform verify and adversarial review before merge-test. The reader is the product’s critical path — correctness over speed.

---

## 12. Agent evidence appendix (abbreviated)

| Cluster | Agents | Outcome |
|---------|--------|---------|
| Snap r3 | 5 adversarial | **5/5 PASS** |
| Chrome area | 1 deep-dive | C1–C10 inventory |
| TTS area | 1 deep-dive | Mitigations vs open T1–T10 |
| ANN area | 1 deep-dive | ANN/SRC inventory |
| Arch area | 1 deep-dive | A1–A7 + must-not-regress |
| Chrome fix validators | 3 | C1/C3/C4 3/3; C2 2/3; C6 freeze consensus |
| TTS fix validators | 3 | T1 solid; T2 re-spec; T3 honesty; T4 omit |
| ANN fix validators | 3 | ANN-7/9 solid; ANN-8 constrained; recolor optional |
| Arch fix validators | 3 | A1 hard gate; A2 mostly done; A4 phased |

Full agent transcripts live in the session tool logs; this file is the durable consensus artifact.

---

*End of handoff. Update this file when major residuals close so the next agent starts from truth, not archaeology.*
