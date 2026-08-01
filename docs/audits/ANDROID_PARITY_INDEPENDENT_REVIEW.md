# Android parity — independent review (context-preservation log)

**Started:** 2026-08-01 00:06 local, by Claude Sonnet 5, working solo overnight on the
owner's laptop (plugged in, sleep disabled, bypass-permissions mode on). Two session
wake-timers set (05:11 and 10:16 local) in case a usage-limit gap interrupts this.

**Ask (owner, verbatim intent):** find the branches Grok used to bring Android to parity
with iOS, review the changes, confirm no silent bugs/regressions, confirm behavioral 1:1
parity across all app sections, use subagents freely, document findings in two forms —
this context log, and a final report with a technical + plain-English section per finding
— then fix what's found to the best of my ability.

This file is the working log: what was checked, in what order, and why, so a session
interrupted mid-review can pick up without re-deriving everything. The user-facing
deliverable is a separate file: `ANDROID_PARITY_REPORT.md` (written once the review
workflow returns).

---

## 1. Locating the work

`git branch -a` / `git worktree list` on the repo root found **21 `android/*` branches**,
each already checked out as its own worktree under `.claude/worktrees/android-*`, organized
in three waves plus four UI-parity passes:

- `android/wave1-w1-{account,detail,home,library,nav,settings}` (6)
- `android/wave2-w2-{bulk,collections,dlqueue,dualtitle,purge,stats}` (6)
- `android/wave3-w3-{ao3-collections,authors,fonts,series-dl}` (4)
- `android/ui-parity-ui-{account,browse-settings,library,workdetail}` (4)
- `android/sync-from-hig-review` — the integration branch all 20 of the above are merged
  into, in order (confirmed via `git log --oneline android/sync-from-hig-review`, which
  shows 20 merge commits, one per branch above, plus 4 more "Android ui: ..." commits for
  the UI-parity passes and a handful of docs commits)

**Decision:** review `android/sync-from-hig-review` as the single integration point
(current tip `5ad08eb8`) rather than the 20 branches individually — it already contains
everything, and that's what a fix would land on anyway.

One repo-hygiene issue found in passing, not touched: `git fetch --all` partially failed
on a corrupted ref name (`android/sync-from-hig-review 2`, literal trailing space+2, both
local and on `origin`). Flagged for the owner in the final report; not deleted without
confirmation since it's tangential to this task and ref deletion is a git operation I
shouldn't take unprompted.

Also found: `main` (and every android branch) contains the Android project in-repo, at
`android/` — this is a monorepo, not a separate repo. Kotlin/Jetpack Compose, package
`io.github.cidy02.kudos`, Gradle 9.4.1, Kotlin 2.3.21 (K2), Room for persistence.

Set up `.claude/worktrees/hig-review-reference` as a plain read-only checkout of
`hig-review` @ `29cd9158` (current iOS tip at the moment this review started) so review
agents have a stable iOS comparison point regardless of what happens on my own working
branch (`claude/native-api-audit-fixes`) meanwhile.

## 2. Grok's own audit trail (read before designing my own review)

Found three existing docs already in `android-sync-hig-review`'s `docs/audits/`:
`IOS_ANDROID_DOMAIN_AUDIT.md`, `REMAINING_PARITY_AND_UI_GAPS.md`,
`ANDROID_HIG_REVIEW_SYNC.md`. Read the first two in full before finalizing review scope,
specifically to avoid re-reporting things Grok already knows and has documented as
deferred (that would waste the owner's time re-reading the same gap twice).

**`REMAINING_PARITY_AND_UI_GAPS.md` (2026-07-31, the more recent/authoritative one) —
explicitly deferred, NOT to be reported as new findings:**
1. Non-EPUB (PDF/HTML/txt) import — Android is EPUB-only
2. Folder / iCloud-style sync — "Android path TBD"
3. Full author profile pages / Inbox hub — Grok's doc says these are "not present as
   first-class Features on this iOS tip", which needs a sanity check: iOS's
   `AuthorProfileView.swift` and Inbox (`AccountInboxViews.swift`) do exist and have grown
   substantially this session. Told the `author` review agent to reconcile this claim
   against the *current* iOS feature set rather than trust the doc at face value — Grok's
   snapshot may predate a lot of this session's iOS work, or "first-class" may mean
   something narrower (e.g. not a top-level tab) than it first reads.
4. Reader device polish (progress pill timing) — 🟡 partial, "needs human device compare"
5. Biometric reveal for mature works — listed as missing; told the `library`/`uicomponents`
   reviewers to confirm whether mature-content *gating* exists at all without the
   biometric reveal step, since that's a privacy-relevant distinction worth being precise
   about even though the biometric piece itself is a known, accepted gap.
6. "Remote compact-card download-into-reader open path" — this is iOS's T-178/T-179
   (Account-tab cards downloading-and-opening on tap), which I built *hours ago this same
   session*. Correctly out of scope; told review agents not to flag it.

Also explicitly marked **not a parity blocker, ever**: Liquid Glass / peel dismiss / zoom
transitions (all iOS-only chrome, some of it — the zoom transition — built literally
tonight). This matches the boundary I'd already put in every review agent's prompt
independently, which is a good cross-check that the scoping is right.

**`IOS_ANDROID_DOMAIN_AUDIT.md` (older pass, useful for what it flagged as still-open
P0s that the newer doc doesn't explicitly confirm as resolved) — worth the `network-write`
and `backup` reviewers specifically re-checking against *current* code rather than trusting
either doc:**
- `AO3RedirectCookieRelay` + session restore validation — flagged P0, networking
- Backup `progressModifiedAt`/`lastModifiedAt` Room fields + last-write-wins merge +
  tombstone table — flagged P0. The newer doc claims backup "v1–v8 merge: Done", but does
  not explicitly say tombstone/LWW conflict handling was later completed — these could be
  two different senses of "done" (decodes the format vs. correctly resolves a two-device
  conflict). **This is the single highest-stakes ambiguity found before the review even
  started** — a backup restore that silently picks the wrong side of a conflict is a
  real data-loss bug, not a cosmetic gap, and I don't have a doc that confidently says
  which state it's actually in. Told the `backup` reviewer explicitly to nail this down
  from the current code, not from either doc.
- Reader TOC + chrome + settings sheet — flagged P0, matches "reader device polish"
  in the newer doc's deferred list, so likely the same known gap under two names.
- "Reading queues / annotations apply (decode only)" — same shape of concern as the
  backup LWW item: if backup import can *read* old queue/annotation data but doesn't
  *apply* it, a restore silently drops that data with no error. Told the `backup`
  reviewer to check this specifically and, if still true, report it at appropriate
  severity (this is a real, if known, data-loss-shaped gap — worth a precise severity
  call rather than either silence or alarm).

## 3. Build/test health, independent of the code review

Two independent checks, since "sound" includes "does it actually build and pass its own
tests," which a pure code-reading review can't fully answer.

- JDK: no system Java; used the JBR bundled with Android Studio
  (`/Applications/Android Studio.app/Contents/jbr/Contents/Home`, OpenJDK 21.0.10).
- Confirmed no other process is actively mutating the `android-sync-hig-review` worktree
  before trusting it as a stable read target for 20+ parallel review agents: the two
  long-lived Gradle/Kotlin daemon processes found via `ps` are both `PPID 1` (detached,
  normal daemon behavior, not evidence of a live foreground session), nothing in the
  worktree had a modification time in the last 20 minutes, and `git status`/`git log -1`
  were stable across repeated checks.
- Ran `android/Scripts/verify.sh` (Grok's own DoD gate: invariants → unit tests →
  assembleDebug → a persistence-focused test subset → whitespace) in the background —
  result pending as this log entry is written; see the final report for the outcome.

## 4. Review workflow

Launched as a background `Workflow` (run id `wf_624fcdc5-ea2`) rather than done solo,
per the owner's explicit go-ahead to use subagents. 22 area-scoped review agents, each
given: the exact Android files to read, a starting (not authoritative) hint at the iOS
counterpart, an explicit list of what does *not* count as a finding (platform-appropriate
Compose/Material differences, and the very-recent iOS-only reader chrome already listed
above), and a required structured output (technical + plain-English summary per finding,
severity, confidence).

Every candidate finding then goes through adversarial verification: three independent
agents, each arguing a different way a finding could be wrong (does it actually reproduce
when re-read from scratch; is it actually just a legitimate platform difference; is the
claimed user-facing impact real) — a finding needs 2 of 3 to survive. This exists because
a single reviewer's plausible-sounding finding is exactly the failure mode worth guarding
against on a task this size, run unsupervised overnight.

The 22 areas (each pipelined: verification of area N's findings starts as soon as area N's
review returns, without waiting for area N+1):

nav, home, library, workdetail, downloadqueue (incl. non-EPUB-import check and
series-download-via-queue), account, settings (incl. custom fonts), browse, search,
statistics, collections, readingqueues, purge, author, reader (incl. an explicit,
concrete check against iOS's `ReaderPageSkeleton` bugs fixed earlier tonight — theme-color
flash, spinner-after-skeleton, fill-height clipping — to see if Android's own
`ReaderPageSkeleton.kt` has an analogous version of any of them), auth, comments, backup
(flagged data-integrity-critical in its own prompt), network-read, network-write (flagged
silent-write-failure-critical), data/persistence, uicomponents+theme.

## 5. Third Grok doc: `ANDROID_HIG_REVIEW_SYNC.md` (read after the workflow was already
launched — used to filter/annotate results, not to change the already-running scope)

This one is dated the same day and turns out to document a pass that ports **exactly**
the iOS commits from earlier tonight this session: `f1f2844` (compact-card tap rule),
`436d65f` (one-stat-per-row cover-card stats), `5f2c3a8` (reader open skeleton),
`3d5765d` (Account-tab cards open the work), pinned against iOS tip `29cd915`. Confirms
the two codebases really are being kept in near-lockstep, and gives precise, checkable
claims for the `home`/`library`/`reader`/`uicomponents` reviewers' findings to be
weighed against:

- Claims Android's `ReaderPageSkeleton.kt` was built to avoid the *same three* bugs my
  `5f2c3a8` fixed (theme-background flash, spinner racing the first real page,
  not filling the available height). This is a claim, not a given — it's exactly what
  the `reader` area's adversarial "reproduces" lens exists to check independently rather
  than take on faith. A finding here would be genuinely new even though the *feature*
  isn't: the tricky part of my original bugs (the fill-arithmetic off-by-one, the
  double-safe-area padding) is exactly the kind of subtlety a description like "fills
  height" can miss while still being true in the broad strokes.
- Explicitly, self-documented as **not yet done** (own P0, section 7): remote/AO3 cards
  still open to Work Detail on tap, not download-then-read — the full `f1f2844` rule
  only landed for already-local cards. **Do not report this as a new finding** — it's
  Grok's own next task, already written up with a suggested TASKS.md entry.
- Explicitly deferred, P1: loading skeletons for Search/Browse/Account lists (only the
  reader got one this pass). If the `search`/`browse`/`account` reviewers notice this,
  annotate it as already-known rather than presenting it as newly discovered.
- Home shelf limit raised 4→12 "to match iOS carousel prefix scale" — matches what I
  recall of iOS's own `.prefix(12)` calls in `HomeView.swift`; a cheap corroboration for
  the `home` reviewer to confirm rather than take on faith.
- Card sizing deliberately NOT cloned 1:1 (164×228 SwiftUI tile abandoned for
  176.dp × min-220.dp content-sized MD3 cards) — a **conscious, documented, correct**
  platform difference. Not a finding no matter which reviewer notices the size differs.

**Known-gaps registry to filter the final findings against** (compiled from all three
Grok docs, before reading the workflow's results):
non-EPUB import · folder/iCloud sync · full author profile / Inbox · reader TOC/chrome
polish / TTS / annotations product · biometric mature-content reveal ·
remote-card-download-then-read · redirect-cookie relay (status unconfirmed — told
`network-write` to check current code) · backup tombstone/LWW conflict merge (status
unconfirmed — told `backup` to check current code) · reading-queue/annotation *apply* on
backup restore (status unconfirmed — same) · Search/Browse/Account list skeletons ·
advanced search filter UI · zoom/peel/Liquid Glass (never porting, by design).

A finding that only restates one of the above, without adding a new severity-relevant
fact (e.g. "and it silently drops data" where the doc only said "deferred"), gets folded
into the report's *Known, already-tracked gaps* section rather than presented as a fresh
discovery.

## 6. `verify.sh` first run: a false alarm, self-inflicted — worth recording so it isn't
mistaken for a real finding later

First `Scripts/verify.sh` run failed at step 2 (`compileDebugKotlin`) with
`IllegalStateException: Storage for [...source-to-classes.tab] is already registered`,
`BUILD FAILED in 6m 7s`. **Not a code defect.** This is Kotlin's incremental-compilation
cache getting corrupted by my own earlier `./gradlew compileDebugKotlin` invocation,
which I had force-killed after it ran past a 590s background-command cap while cold-
compiling (a first Compose/K2 build of ~194 files is genuinely slow, and I hadn't yet
found `Scripts/verify.sh` or realized the kill would leave a stale lock on disk).

Also worth a note for future me: the task-notification for this run reported
"completed (exit code 0)", which is **not trustworthy** here — my background wrapper was
two sequential statements (`sh Scripts/verify.sh > log; echo exit=$? >> log`), and the
harness's own reported exit code reflects the *last* statement (`echo`, which always
succeeds), not the actual script. The real result was in the log itself
(`android verify exit=1`). Read the log, don't trust the notification summary's exit code
for a multi-statement background command.

**Fix applied:** `./gradlew --stop` (stopped the one stale daemon) + deleted
`app/build/kotlin/compileDebugKotlin` (a build-output cache directory, not source) +
re-ran `Scripts/verify.sh` from clean. Re-run in progress; result in the next entry.

## 7. Status at last update

`verify.sh` re-run in flight (clean cache this time) and the 22-area review workflow
(`wf_624fcdc5-ea2`) still running. Results, the confirmed verify.sh outcome, and any
fixes applied afterward go into `ANDROID_PARITY_REPORT.md` once the workflow returns.
