# Critical self-review — reader TTS, mini player, highlights (session 2026-07-27)

**Branch:** `from-keen-cori-d0a989`  
**Base:** `claude/keen-cori-d0a989` @ `9402456` + reader redesign commits through `33349be`  
**Device install:** `Kudos-NewReader` (`com.cidy02.Kudos.NewReader`) installed and launched on Yan’s iPhone (2026-07-27). Original `com.cidy02.Kudos` left in place.  
**Review stance:** adversarial. No code changes in this pass — findings only; wait for human go-ahead before fixing.

---

## Scope of this session

| Area | What landed |
|------|-------------|
| **Carry-over WIP** | Claude’s uncommitted reader redesign extras (TTS, highlights host, notes, search, orientation lock) onto a branch off keen-cori |
| **Mini player chrome** | TTS strip inside bottom position card + separator only while active; stop control (not ×) |
| **TTS Phase 1** | Voice catalog (no Personal Voice), rate/pitch prefs, sentence pause, Read Aloud settings section |
| **Fan menu TTS** | Active waveform = full stop (same path as mini-player stop), not pause |
| **Highlights** | Tap to edit/delete; toggle-off same span; list bare marks; floating colour bar after Highlight; last-used colour |
| **A/B install only** | Temporary pbxproj rename to `Kudos-NewReader` / `com.cidy02.Kudos.NewReader` (+ `PRODUCT_MODULE_NAME = Kudos`) |

**Not committed.** Working tree is dirty; pbxproj identity change is local test scaffolding.

---

## Severity legend

- **P0** — wrong behaviour users will hit; fix before merge  
- **P1** — real bug or clear UX footgun; fix soon  
- **P2** — polish / edge case / maintainability  
- **Note** — context, not necessarily a defect  

---

## P0 / P1 — bugs and regressions

### 1. [P0] Mini player and position card vanish when chrome auto-hides during TTS

`positionCardLayer` is gated on `chromeVisible` (opacity + hit testing). Starting read-aloud does **not** pin chrome visible. A page tap (or auto-hide) hides the **entire** bottom card — including transport — while speech may still be playing.

**Why it hurts:** Fan-menu stop still works if chrome is shown, but the natural “I’m listening” affordance disappears. We already identified this earlier and did not fix it in Phase 1.

**Mitigation directions (for later):** (a) keep position card / mini strip visible while `speech.status != .stopped`, independent of chrome; (b) pin chrome while speech is active; (c) ship Now Playing / remote commands so controls exist outside the reader chrome.

(Human review) fix this by decoupling the mini-player from the bottom card ONLY when TTS is active and user dismisses chrome, and recouple when showing chrome again. Make this animate cleanly.

---

### 2. [P1] Dual audio-session ownership (app + Readium)

`ReaderSpeechController` activates/deactivates `AVAudioSession` itself **and** `PublicationSpeechSynthesizer` uses Readium’s `AudioSession` with `.spokenAudio` / long-form policy.

**Risks:** race on stop/start; “other apps unduck late”; intermittent silent start after interrupting another app; stop() sets status before engine fully settles.

**Mitigation:** let Readium own the session (preferred) or document a single owner and remove the other path.
(Human review) make the necessary changes to have Readium own the session.

---

### 3. [P1] `prepare()` tears down speech every time `book.phase` becomes `.ready`

```text
stop() → nil synthesizer → rebuild
```

If `.ready` fires more than once for the same open (or a future code path re-enters ready), an in-progress session is killed. Today open is mostly one-shot, but the API is fragile.

**Also:** `onAdvance` is reassigned on each ready; fine, but pairs with full rebuild cost.
(Human review) clarify to me in plain English what this means and what your recommendation is

---

### 4. [P1] Fan “read aloud” no longer supports pause-from-menu

By design this session: active waveform = **stop**, not pause. Pause lives only on the mini player.

**Regression vs earlier Claude WIP:** users who hide chrome and open the fan expecting pause get a full stop. Combined with **#1**, the only pause control can be invisible.

**Product call needed:** start/stop only (current), or start / pause / stop with distinct icons.
(Human review) The mini player has pause, so there is already a flow for users to pause/resume. This “regression” is intended, so long as no other issues are caused.

---

### 5. [P1] Highlight “same passage” matching can false-positive

`ReadingAnnotationMatching` falls back to:

- identical non-empty `selectedText` **and** same Readium `position`, or  
- identical text when **both** positions are nil  

**Risks:**

- Repeated short phrases in the same position bucket (“yes”, character names) → Highlight toggles off the **wrong** earlier mark or refuses a second mark.  
- Partial re-selection of a longer highlight (substring) may not match locator → **second** mark stacked (duplicates still possible for overlapping, non-identical ranges).  
- Expanding a selection that shares a prefix with an old snapshot won’t match → stacked highlights.

There is **no geometric / CFI range overlap** logic — only locator string equality or text+position.
(Human review) clarify to me in plain English what this means and what your recommendation is

---

### 6. [P1] Colour bar is easy to miss / easy to leave orphaned in mental model

- Fixed near **bottom**, not near selection (system menu can’t host a picker; we chose a bottom glass bar).  
- Not dismissed by page tap / chrome hide / navigation — only colour pick, ×, delete, or new highlight.  
- Stacks awkwardly with position card + optional mini player (**magic `+ 88` bottom padding** — layout debt; will collide if card height changes).  
- Tapping the same swatch as current colour only dismisses; no “keep bar open to experiment”.

**Intuition gap:** many users expect colour **before** mark, or a menu next to Highlight. Last-used + post-hoc bar is reasonable but not discoverable on first use.
(Human Review) How do you propose we fix this?

---

### 7. [P1] Temporary A/B identity still in `project.pbxproj`

Local-only settings still dirty:

- Display name `Kudos-NewReader`  
- Bundle id `com.cidy02.Kudos.NewReader`  
- Product name / TEST_HOST adjusted  
- `PRODUCT_MODULE_NAME = Kudos` (good for tests)

**Must not be committed.** Easy to forget; CI/signing/docs assume `com.cidy02.Kudos`.
(Human review) this will be fixed right before we merge to the original branch, for now we need the new name and bundle ID for testing.

---

## P2 — design / over-engineering / consistency

### 8. [P2] Generic `ReaderPositionCard<MiniPlayer>` + `EmptyView` type check

`showsMiniPlayer` uses `MiniPlayer.self != EmptyView.self`. That works with the **if/else call-site** pattern, but is brittle: a future `if speech { mini } else { EmptyView() }` inside one builder would make the type `_ConditionalContent` and keep the separator forever.

**Simpler alternative:** `showsMiniPlayer: Bool` + optional `@ViewBuilder`, or always pass a Bool flag.

---

### 9. [P2] Duplicated `ReaderPositionCard(...)` construction

Two nearly identical initializers in `positionCard` for speech on/off. Fine for a small surface; a single builder with a Bool would shrink noise.

---

### 10. [P2] TTS settings surface area vs value

Phase 1 delivered:

- Voice list (good)  
- Rate + pitch sliders  
- Reset  
- Footer about system Enhanced/Premium downloads  

Pitch is a relatively weak lever for long-form prose; rate + voice dominate. Not wrong, but denser than necessary for v1.

**Missing:** live sample (“play a sentence”), language override when EPUB language is wrong, per-work language.

---

### 11. [P2] No spoken-text cleanup on the actual audio path

`cleanUtteranceText` is tested and used for the mini-player caption only. Readium’s `TTSUtterance` init is internal, so we can’t rewrite engine text without a custom `TTSEngine`. Honest limitation; the helper’s name oversells the feature.

---

### 12. [P2] Contents segment still labelled “Notes” but lists all highlights

Bare highlights now appear (good for delete). Label/empty state say “Highlights” in empty title but segment title remains **Notes**. Mild IA confusion: bookmarks vs notes vs highlights.

---

### 13. [P2] Re-Highlight always deletes; never “change colour via menu”

Toggle-off on second Highlight is Apple-ish, but:

- User selects same span wanting **green** after yellow → Highlight **removes** instead of recolouring.  
- Colour change requires tap mark / colour bar / note editor.

Document or offer: second Highlight with a different last-used colour could **replace colour** instead of delete.

---

### 14. [P2] Orientation lock is session-only singleton via app delegate

Reasonable Books-like design. Risks:

- Failure if `activeScene` is nil at lock time (silent no-op).  
- Only one shared lock for the whole app process (fine while one reader).  
- Extra `UIApplicationDelegateAdaptor` surface area for a single feature.

---

### 15. [P2] Search / notes / highlight host files are large WIP carried from Claude

Session also pulled:

- `ReaderSearchView`, `ReaderNoteEditor`, `ReaderHighlightHost`, orientation lock, Models annotation bits  

Not all of that was design-reviewed in depth here. Search has known deprecation warnings (`Text` `+`). Treat as **imported WIP**, not session-proven.

---

### 16. [P2] Tests are narrow

| Suite | Covers |
|-------|--------|
| `ReaderSpeechPreferencesTests` | cleanup string, voice resolution |
| `ReadingAnnotationMatchingTests` | matching pure function |

**Not covered:** chrome+speech interaction, stop path parity, colour bar lifecycle, decoration tap → editor, prepare() rebuild, audio session, UI for settings.

---

## Un-intuitive design summary

| Behaviour | Why it may confuse |
|-----------|-------------------|
| Fan waveform stops completely when active | Looks like a “playing” indicator; users may expect pause |
| Mini player dies with chrome hide | Transport should feel “session sticky” while speaking |
| Colour bar at bottom after Highlight | Not next to selection; easy to miss |
| Second Highlight deletes | Wanted recolour → surprise deletion |
| “Notes” tab holds all highlights | Naming lag |
| Automatic voice needs system Enhanced downloads | Footer helps; still a system-settings detour |

---

## What looks solid

- **Mini player inside one glass card** with conditional separator — clean chrome, matches the “4a” density goal.  
- **Shared `stopReadingAloud()`** for fan / mini stop / reader dismiss — correct consolidation.  
- **No Personal Voice** — product-consistent for fanfic.  
- **Decoration tap → editor** with Delete Highlight — primary gap for “can’t remove” closed.  
- **Bare highlights in the sheet** + swipe delete — second recovery path.  
- **Last-used colour + post-create bar** — pragmatic given `UIMenuItem` limits.  
- **Underline as `.underline` decoration** — matches palette semantics.  
- **Tombstone on annotation delete** — stays on the persistence rails.  
- **Side-by-side install** with module name pinned — workable A/B without breaking `@testable import Kudos`.

---

## Suggested fix order (when you green-light work)

1. **P0:** Keep mini player (or full position card) available while speech is active regardless of chrome.  
2. **P1:** Single audio-session owner (prefer Readium).  
3. **P1:** Soften highlight matching (prefer locator-only for toggle-off; require stricter overlap for “same”).  
4. **P1:** Dismiss colour bar on chrome hide / page turn / selection change; replace magic `88` with layout relative to card.  
5. **P1:** Revert or fence pbxproj A/B identity before any commit.  
6. **P2:** Fan control semantics (pause vs stop) product decision.  
7. **P2:** Rename Notes segment or split Highlights.  
8. **P2:** Collapse `ReaderPositionCard` API / call-site duplication.

---

## Manual test checklist (device: Kudos-NewReader)

Use this on the install just pushed:

**TTS**

- [ ] Start read-aloud from fan; mini strip appears in bottom card with separator  
- [ ] Pause/play on mini; stop on mini dismisses strip only, chrome stays  
- [ ] Stop from fan waveform while playing → strip gone  
- [ ] Hide chrome during speech → **confirm whether controls vanish (expected P0)**  
- [ ] Change voice/rate/pitch in Themes & Settings → next utterance reflects change  
- [ ] Leave reader while speaking → speech stops  

**Highlights**

- [ ] Highlight text → colour bar appears; pick colour; mark updates  
- [ ] Highlight same span again → mark removed  
- [ ] Tap mark → editor → delete  
- [ ] Bare highlight appears under Bookmarks & Notes → Notes; swipe delete  
- [ ] Overlapping / repeated short phrase → check false toggle  

**Chrome**

- [ ] Colour bar + position card + (optional) mini player don’t overlap unusably  
- [ ] Rotation lock toggles and releases on dismiss  

---

## Commit hygiene reminder

Before any PR / merge:

1. Revert A/B pbxproj (or keep only on a local uncommitted stash).  
2. Split commits if possible: TTS prefs vs highlight UX vs chrome mini player.  
3. Do not leave `PRODUCT_BUNDLE_IDENTIFIER = com.cidy02.Kudos.NewReader` on a shared branch.

---

## Bottom line

The session moves the reader redesign WIP toward something shippable: **one-card mini player**, **usable TTS prefs**, and **actually deletable highlights with a colour path**. The highest-risk unfinished item is **transport disappearing with chrome during TTS** (P0). Next is **audio session dual ownership**, **highlight identity heuristics**, and **not committing the temporary bundle id**.

No code was changed for this review. Awaiting go-ahead on which findings to fix first.

---

# Follow-up self-review — delta since § above (later same day)

**Reviewed:** changes *after* the initial write-up of this file (~16:34).  
**Stance:** same criteria (bugs / regressions / over-engineering / unintuitive design). No code changes in this pass.  
**Prior findings #1–#16 remain open** unless noted as mitigated below.

### Delta scope (what landed since first review)

| Area | Change |
|------|--------|
| **System voices deep link** | `SystemSpokenContentSettings` + “Download Enhanced & Premium Voices…” in Read Aloud / Voice picker |
| **Fan icon theming** | Pill/round/more glyphs use theme tint; labels stay primary |
| **Emphasized round actions** | Rotation lock + TTS: solid theme capsule + white icon when active |
| **Symbol motion** | `.contentTransition(.replace)` on round icons; rotation lock adds one-shot `.rotate.byLayer`; TTS/lock toggles use `withAnimation` |
| **Fan morph timing** | Spring `0.34/0.82` → `0.44/0.88` (calmer) |
| **Title pill** | Person icon + author (no “by”); tap → push `WorkDetailView` |
| **Chrome open flash** | Full-size host while loading so overlays aren’t laid out on a centred ProgressView |

---

## New findings (#17+)

### 17. [P1] Title pill → work details can stack a second detail on an existing detail→reader path

Opening details uses:

```text
.navigationDestination(isPresented: $showingWorkDetail) { WorkDetailView(work: work) }
```

Common path: **Library → WorkDetail → Reader**. Tap title pill → **Reader → WorkDetail (again)**. Stack becomes Detail → Reader → Detail′. Back from the second detail returns to the reader (good), but you now have two detail instances and can re-enter reader from the upper detail → easy stack bloat.

**Also:** `navigationDestination(isPresented:)` is the older isPresented form; fine on current SDKs but item-based destinations are preferred elsewhere in the app (`LocalWorkDestination`).

**Mitigation ideas:** if the previous VC is already this work’s detail, `dismiss()` instead of push; or present detail as a sheet from the reader; or navigate via a single shared route that replaces rather than stacks.

---

### 18. [P1] Undocumented Settings URL schemes (`App-prefs:` / `prefs:`)

`SystemSpokenContentSettings` walks private deep links to Accessibility → Spoken Content. On many OS versions this works; it is **not** a public API.

**Risks:**

- Silent no-op or wrong screen after an iOS update  
- App Review friction if shipped (prefs URL schemes have a history of rejections)  
- Completion-handler fallback is sequential but still may “succeed” opening Settings root while never reaching Voices  

**Mitigation:** keep as best-effort with clear copy; consider also linking Apple’s support article; retest on each major iOS; do not depend on exact SPEECH path for core functionality.

---

### 19. [P1] Emphasized (filled) buttons always use pure white glyphs

Active lock/TTS use `Color.white` on `action.tint` fill.

**Risk:** if the user sets a very light accent (or a future theme maps “tint” to something pale), contrast fails WCAG. Current defaults (AO3 red, sepia brown) are fine.

**Mitigation:** pick white vs near-black from relative luminance of `tint`, or use `Color(uiColor: .label)` inverted against the fill.

---

### 20. [P2] TTS emphasized while **paused** (mini player still up)

`speechActive = speech.status != .stopped` → fan waveform stays filled when paused.

**Pros:** matches “session on” / mini player present; stop is still the fan action.  
**Cons:** filled state no longer means “audio is playing”; user may think speech is still audible while paused.

**Product call:** emphasize only for `.playing`, or keep as “session active” (current). Document in a11y label (already “Stop reading aloud” when active — good).

---

### 21. [P2] `isEmphasized` + `.glassEffect(.clear)` may interact oddly with fan morph

While emphasized, glass is cleared and a solid `Capsule` fill is drawn. Slot still has `glassEffectID`. Opening/closing the fan with lock or TTS already active could produce a one-frame glass/fill flash or morph mismatch vs neighbouring glass pills.

**Mitigation:** visual check on device when opening fan with lock on and TTS on; if janky, keep regular glass and use a tinted material, or apply fill *inside* the glass shape.

---

### 22. [P2] Hard-coded `action.id == "rotationLock"` for arrow spin

Rotate effect is gated on string id `"rotationLock"`. Fragile if id renames; TTS doesn’t get a live “speaking” symbol pulse (intentional for now).

**Mitigation:** `var symbolMotion: …` on `ReaderFanRoundAction` instead of magic ids.

---

### 23. [P2] Kudos / bookmark still rely only on outline vs fill (no capsule fill)

After lock/TTS gained strong selected chrome, kudos-given and bookmarked states look comparatively weak (theme outline/fill symbol only). Consistency gap, not a bug.

**Optional:** emphasize kudos when given and bookmark when on (same pattern). Kudos-given is also **disabled**, so a filled capsule that can’t be tapped needs a clear “already given” a11y state.

---

### 24. [P2] Title pill author is a single flat string + generic person icon

`work.author` is display text only — no multi-author routing, no verified `AO3AuthorIdentity` bylines (unlike library cards / work detail). Pill tap opens **work** details, not the author profile. Fine for v1; don’t mistake the person glyph for a tappable author link.

---

### 25. [Note / mitigated] Chrome buttons flashing centre on open

Root cause was overlays sized to a centred `ProgressView` host. Fixed by always using a full-screen frame for content/host. **Not fully re-verified on device in this write-up** — still worth a manual open of a large EPUB.

Does **not** fix finding **#1** (chrome hide during TTS).

---

### 26. [Note] Positive deltas (no issue)

- Fan morph calmer (`0.44` / `0.88`) — good Books-like direction.  
- Theme-tint icons + primary labels — clear hierarchy.  
- Lock/TTS filled selected states — much better state legibility than symbol-only.  
- Lock arrow spin + replace — appropriate use of SF Symbol effects.  
- Voices download control — better than a multi-step footnote alone.  
- Dropping “by” from the author line — less busy; person icon retained.

---

## Prior findings — status after delta

| # | Status |
|---|--------|
| 1 P0 chrome hides mini player during TTS | **Still open** |
| 2–7 P1 | **Still open** (pbxproj A/B still dirty) |
| 8–16 P2 | **Still open** |
| — | **#25** new note: open-flash layout fixed |

---

## Updated fix order (includes delta)

1. **P0 #1** — Mini player / position card while speech active  
2. **P1 #17** — Title-pill work-details navigation strategy (dismiss vs stack)  
3. **P1 #2** — Single audio-session owner  
4. **P1 #5** — Highlight matching  
5. **P1 #6 / #4** — Colour bar lifecycle + layout  
6. **P1 #7** — Revert A/B pbxproj before commit  
7. **P1 #18** — Document/retest prefs deep links; support-article fallback  
8. **P1 #19** — Contrast-aware glyph on filled capsules  
9. **P2** — Fan pause-vs-stop, Notes naming, kudos/bookmark emphasize parity, magic ids  

---

## Extra manual checks (delta)

- [ ] Open reader cold: chrome never appears mid-screen  
- [ ] Title pill → work details from Library→Reader and from Detail→Reader; note stack behaviour  
- [ ] Download Voices… lands somewhere useful (Spoken Content or Accessibility)  
- [ ] Lock on: filled capsule + white icon + arrow spin; fan open/close with lock already on  
- [ ] TTS on: filled capsule + white waveform; still filled when paused; stop clears fill  
- [ ] Light accent colour (if customizable): white glyph still readable  

---

## Bottom line (follow-up)

Polish after the first review mostly **improved state clarity** (lock/TTS fill, theming, calmer fan, voices link, open-flash fix). New material risks are **navigation stacking from the title pill (#17)**, **private Settings URLs (#18)**, and **white-on-tint contrast (#19)**. The original **P0 TTS chrome-hide** is still the biggest functional gap.

No code was changed in this follow-up review pass.
