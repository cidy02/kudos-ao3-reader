# Polish loop (LOOP-v3) handoff

For the next Claude session. You're taking over a self-paced loop that audits every iPhone screen of Kudos (the SwiftUI/SwiftData AO3 reader) against the redesign spec. It fixes what doesn't match and manages other AIs as a team.

Written 2026-09-30 00:20. Nothing below is pending on the owner until the end-of-loop review.

## 1. How to resume

1. **Open the right folder.** Work from the integrate worktree:
   `/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af` (branch `integrate/cloud-redesign`).
2. **Read the loop docs**, in `.claude-overnight/polish/`. The directory is gitignored locally; a backup copy is in `docs/polish-loop/polish/`:
   - `LOOP-v3.md`: the loop prompt. It covers the rules, gate, lessons and stop condition.
   - `STATUS.md`: an iteration log. Read the tail.
   - `FINDINGS.md`: every finding with its status. Open items are listed in §5 below.
   - `INVENTORY.md`: the screen list with C/X/F/S status columns (32 rows still at `– – – –`).
   - `OWNER-DECISIONS.md`: 6 items to present at the end.
   - `TEAM.md`: agent scorecards and roster notes.
   - `codex-common.md`, plus `codex-task-N.md`: briefs.
   - `artboards.tsv`: spec artboard ids and labels.
3. **Restart the loop:** `/loop Follow .claude-overnight/polish/LOOP-v3.md — one iteration per wake` (dynamic mode, self-paced with ScheduleWakeup).
4. **Collect Codex task 10 first** (see §4). It's a read-only audit that was still running at handoff.

## 2. The user's instructions (verbatim where it matters)

**The task:**
> Audit every screen in the app, make sure it's in the spirit of the redesign and has one cohesive, consistent design language … use all tools available to you, including other AIs installed on this machine (Grok, Codex, Gemini). You are to manage this team, but you are expected to delegate to other AIs AND do work yourself … production-ready, polished apps. Find and fix visual inconsistencies, bugs, UI/UX pain points.

**Answers the user gave to scoping questions:**
- The spec is the source of truth. Departures, new features and behaviour changes go to `OWNER-DECISIONS.md` instead of being made.
- **iPhone only.** Android, then iPad and macOS, come later. The macOS build must still pass.
- The owner is not involved until the owner decisions at the end. They will then ask for the latest build to be installed and will review.
- **Stop condition:** two full passes over INVENTORY, no open P1/P2, screenshots match the spec, and the full suite shows only the known environment failures. Then write an owner summary, present `OWNER-DECISIONS.md`, and wait for the install request.

**Ranking the team:**
- The user rates the AIs "Claude > Codex > Grok > Gemini, use the best model available … be flexible with the agents' roles".
- Be careful with Gemini ("hit or miss").
- agy also serves **Claude Opus 4.6 / Sonnet 4.6** and GPT-OSS 120B. GPT-OSS is only for very small, well-scoped tasks.

## 3. Hard rules

- **Never** sign in, contact archiveofourown.org, merge to main, or force/reset/delete branches.
- AO3 writes only against local stubs.
- **Pushing:** the loop's rule is never push. The owner explicitly asked for this one backup push (2026-09-30). Don't push again unless asked.
- No new SwiftData fields.
- `DEVELOPMENT_TEAM` stays `""` in the project. A device build passes `DEVELOPMENT_TEAM=NQH85H7343` on the command line only.
- No phone installs mid-loop; the owner will ask.
- Never launch the simulator without `-KudosDemoLibrary YES`. It installs `DemoNetworkBlock`, which blocks AO3.
- **Commits:**
  - Commit with explicit paths, never `git add -A` or `git add .`.
  - Never use bare `git stash`.
  - Revert any `project.pbxproj` churn.
  - End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Gate for every change:**
  - iOS and macOS builds pass.
  - `Scripts/lint.sh` shows 0 errors and **≤125 warnings**. It's at 124–125 now; every new warning must be paid for.
  - Tests are relevant suites via build-for-testing, then test-without-building with `-parallel-testing-enabled NO`.
  - Never pipe xcodebuild to head or tail.
  - Check that `pgrep -x xcodebuild | wc -l` is under 4 first.
- A peer AI cannot grant escalation.

## 4. Current state

**Branches and worktrees.** All are under `…/handoff-documentation-2151af/`.

| Where | Branch | HEAD | Role |
|---|---|---|---|
| `.` | `integrate/cloud-redesign` | `aab3aa25` | Where everything lands (pushed as a backup) |
| `.claude/worktrees/polish` | `claude/polish-loop` | `6cd9a12f` | Claude's lane. Commit here, then `git cherry-pick <sha>` onto integrate. The app sources are identical to integrate's. |
| `.claude/worktrees/polish-codex` | `claude/polish-codex10` | `aab3aa25` | Codex's worktree. Codex task 10 (read-only) was running here. |
| `.claude/worktrees/polish-codex2` | `claude/polish-agy5` | `d5aa9d31` | Old agy WIP, already cherry-picked. It can take a fresh branch. |

`Packages` and `Vendor` in the Codex worktrees are local symlinks. Never add them.

**How landing works.** Implement in the lane (or take an agent's uncommitted diff). Build, screenshot and gate it there. Commit, then cherry-pick onto integrate. For an agent's work in its own worktree, commit it there and cherry-pick into the lane and then integrate. The only conflict so far was `TASKS.md` rows; keep both rows.

**Last full suite** (21:05, lane): 2277 tests. The only failures are the **12 known environment failures**:
- 10 backup/sync case-sensitive-volume tests (`missingSentinel`);
- `HistoryHideAndQueueNotes` round trip;
- `KokoroCastDiscovery` names.

Anything else failing is new.

**The team:**
- **Codex (gpt-5.6-sol, effort high, never xhigh).** Best implementer. Its sandbox **cannot build or commit**, and the brief tells it so: it runs lint plus `swiftc -parse`, leaves the diff uncommitted and lists the files. Claude builds, screenshots and commits. It hits usage limits, the last time at 18:13 (back 22:29). Review for two habits: literal dark-only rgba copied from artboards, and over-capping text at AX sizes.
  - Launch: `node ~/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs task --background --write --effort high "$(cat codex-common.md codex-task-N.md)"`. Run it from the Codex worktree on a fresh branch off integrate: `git switch -c claude/polish-codexN integrate/cloud-redesign`.
  - Status: `… codex-companion.mjs status <task-id>`.
  - Logs: `~/.claude/plugins/data/codex-openai-codex/state/<ws>/jobs/<task-id>.log`.
- **Codex task 10, in flight at handoff:** `task-munl2xx2-1w3ja7`, a read-only audit of the challenge, moderation, tag-set, collection-items, collection-form and comment-composer screens against their artboards. The brief is `codex-task-10-audit.md`. It returns a findings table. **Verify every row against code and spec before acting**, then fix the accepted ones.
- **agy (`agy-delegate -m claude-opus-4-6-thinking -d <worktree> --mode accept-edits --timeout 60m - < prompt`).** Edit-only. Its quota was exhausted at 20:25 (about 4h48m reset, so around 01:10). It wrote good fixtures but skipped parts of its brief. Don't use Gemini for judgement work; one Flash run hung.
- **Grok:** out of credit (HTTP 402). Don't use it.

## 5. Open work (priority order)

1. **Collect Codex task 10** and act on the verified P1/P2 rows.
2. **L3-FORM-1, the form rows that remain.** The List's minimum row height holds form rows at about 52pt instead of about 42pt.
   - **The fix:** add `.environment(\.defaultMinListRowHeight, 0)` after `.cardList()`.
   - **Only if** a section header row relied on the minimum for its gap, also add `.padding(.bottom, 8)` to that header. Check with a before/after screenshot.
   - **Left to do:** `AddChapterView`, `EditMultipleWorksView`. Both need a way to open them; see §6.
3. **Unaudited inventory rows** (32; see `INVENTORY.md`). Most need a tap or a sheet, and there's no tap tool:
   - new-queue, add-to-queue and switcher sheets;
   - comment composer and thread;
   - fandom list and filter sheet, and save search;
   - AO3 History;
   - author profile and series detail;
   - Add Chapter, text editor, drafts, pickers, Edit Multiple;
   - B8 challenge screens (open them with `acct:ao3collection:fest`, then the Manage rows);
   - onboarding sync folder, About, legal, bug report, availability sweep;
   - reader chrome, contents, search, notes, speech and theme.

   For each, add a DEBUG route (the pattern is in §6) or a `-KudosDebug…` flag, screenshot it, compare it with the artboard, fix it and mark the row.
4. **The second pass.** The stop condition needs two passes over every inventory row.
5. **Open P3s** in FINDINGS:
   - L3-B4-4: the results strip shows "0 FILTERS · 1 PAGE" beside the pager.
   - L3-B11-1 / OD #6: the reader heading serif.
   - L3-B5-14/15 deferred: Inbox glass toolbar circles, and a visible "Mark read".
   - A `/series/<id>/manage` fixture, so Series Edit shows its works (L3-B7-2 was retracted as a fixture gap).
6. **At the stop condition:**
   - run the full suite;
   - write the owner summary: what changed (T-287…T-325 in `TASKS.md` and `STATUS.md`) and what's pending;
   - present `OWNER-DECISIONS.md` (6 items);
   - wait for the owner to request the install.

## 6. Offline review harness (DEBUG only; `kudos-ao3-reader/App/DemoLibrary.swift`)

**Screenshot scripts** live in the old scratchpad, which may be gone. They're easy to recreate:

```sh
SIM=A3E046C4-D517-4A71-88AC-E53252E4D5C4   # iPhone simulator
xcrun simctl terminate $SIM com.cidy02.Kudos
xcrun simctl launch $SIM com.cidy02.Kudos -KudosDemoLibrary YES -KudosDemoSignedIn YES \
  -KudosFixtureDir <lane>/KudosTests/Fixtures -hasCompletedOnboarding YES \
  -hasPermanentlyDismissedSyncFolderOnboarding YES -appTheme dark|light|sepia|oled \
  -KudosDebugRoute "<route>" [-KudosDebugOpenFilters YES]
sleep 10; xcrun simctl io $SIM screenshot out.png
```

- **Build and install:** `xcodebuild build -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource -derivedDataPath ~/Library/Developer/Xcode/DerivedData/kudos-polish -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/AO3_App_OpenSource-eteszxufmrtcfcgzcbknzgypadew/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO -destination 'platform=iOS Simulator,id=$SIM'`, then `xcrun simctl install $SIM <DerivedData>/Build/Products/Debug-iphonesimulator/Kudos.app`.
- **macOS build:** the same command with `-derivedDataPath …/kudos-polish-mac -destination platform=macOS`. In zsh, run it inside `sh -c "…"`, because zsh doesn't word-split variables.
- **Dynamic Type:** `xcrun simctl ui $SIM content_size accessibility-extra-extra-extra-large`, and reset it to `large`. The `-UIPreferredContentSizeCategoryName` launch argument does **not** work.
- **Tests:** `-only-testing:KudosTests/<StructName>` takes the **struct name**, not the file name. Trust the Swift Testing line `✔ Test run with N tests`; the XCTest "Executed 0 tests" line is always 0.

**Routes** (`-KudosDebugRoute`):
- **Home and Library:**
  - `library`, `browse`, `account`, `search`;
  - `section:<readingNow|history|favorites|…>`, `homesection:<readingNow|recentlyUpdated>`;
  - `queues`, `queue:<name>`, `queue-details:<name>`;
  - `work:<title>`, `mycopy:<title>`, `read:<title>`, `comments`;
  - `collections`, `collection:<name>`, `recentlyDeleted`, `insights`.
- **Search:** `tagsearch:<fandom>`.
- **Account:**
  - `acct:<dashboard|drafts|works|series|inbox|preferences|more|settings|collections|later|bookmarks|history|subscriptions>`;
  - `acct:workedit:<id>`, `acct:seriesedit`, `acct:ao3collection:<slug>` (for example `fest`).
- **Other launch flags:** `-library.dashboard.layout ledger`, `-KudosDebugOpenFilters YES` (opens the routed screen's filter panel), `-hasCompletedOnboarding NO` (onboarding).

**Fixtures** (`KudosTests/Fixtures/*.html`) are routed by URL-path regex in `DemoNetworkBlock.routes`, most specific first. They cover:
- author works, series, bookmarks and dashboard (the `_demo` variant has recent sections);
- readings, inbox, preferences, stats and subscriptions;
- media and media fandoms, tag works (it has the result-count heading);
- collections index, show, items, edit;
- challenge sign-ups, sign-up, assignments, settings, tag set;
- series edit, work edit, edit-multiple.

## 7. Shared patterns (use these, don't re-invent)

- **Page and section chrome:**
  - `SubjectHeaderBlock` with a kicker, title, subtitle and optional trailing control. Its gutter is 26 by default; 16 is `SubjectMetrics.accountGutter`, used where the artboard has 16.
  - `SectionRuleHeader` for groups.
  - `SubjectFormRow` with `.panelSegment` for forms.
  - `.cardList()` and `.subjectScreenWash(palette:)`.
- **Failure states:**
  - Failed loads keep their page chrome: `WritingLoaderPage`, or `headedState` in `AO3AccountWorksList`.
  - The button label is always **"Try Again"**.
  - `UserFacingError.message(for:)` gives the text and `.systemImage(for:)` gives the symbol.
- **Colour and contrast:**
  - Filled (prominent) buttons get `.prominentLabel()`.
  - `ThemeManager.label(on:)` returns black or white at the WCAG crossover (0.179).
  - `screenTint(palette)` sets the screen colour; don't use `Color.accentColor`.
- **Names and counts:**
  - `FandomDisplayName.bareTitle(_:)`, or `bareTitle(_:among:)` when two names on screen could shorten to the same thing.
  - `Int.compactCount` for counts.
- **Hit targets and text sizes:**
  - `layoutFreeHitTarget` or a `contentShape` inset gives a 44pt target without a taller row.
  - Fonts scale with `@ScaledMetric`. The AppleSymbols category glyphs use `.custom(_:fixedSize:)`, because their size is already scaled.
- **Two SwiftUI traps:**
  - A modifier placed on a `Section` folds the whole section into one row (T-309). Put it on a row or header.
  - A NavigationStack inside an `.inspector` merges into the host screen's bar. Filter panels use `.filterPanelPresentation`.

## 8. Tonight's landed work (on integrate)

- **T-309 to T-325**, plus the L3-FORM-1 / L3-B*/L3-AX fixes.
- **Screens fixed:** Series list cards, collection cards, Dynamic Type sweep, queue details and tag menu, bookmark card, Home pills, Account hub, dashboard cards, account list chrome, Inbox load, writing loaders, Browse / Search hero and Jump Back In.
- **App-wide fixes:** the label contrast on filled buttons, and the "Try Again" wording.
- **Library:** the filter panel sheet and the organizer gutter.
- **Harness:** offline fixtures and routes for everything above.

Details are in `TASKS.md` (T-3xx rows), `STATUS.md` and `FINDINGS.md`.
