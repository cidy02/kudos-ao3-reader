# Kudos production polish loop (v3) — one iteration per wake

Owner brief, 2026-09-29: audit every iPhone screen so the whole app is in the spirit of the
redesign and speaks one cohesive, consistent design language. Find and fix visual
inconsistencies, bugs and UI/UX pain points until the app is production-ready. Manage a team
of AIs (Codex, Grok, Gemini): delegate what each is best at AND do real work yourself.
For every screen ask: *Does this fit the app? Does it empower the user? Is it one design
philosophy with the rest of the app? Would Apple be proud to ship it?*

The owner is NOT involved until the end. Do not ask questions mid-loop. Anything that needs
the owner goes on the owner-decisions list (below) and waits.

## 0. Authority

- **Source of truth:** `docs/design/Final_Redesign_Spec.dc.html` (104 artboards, labelled by
  `data-screen-label`), then `docs/REDESIGN_DECISIONS.md`, then the code's own owner-dated
  comments ("owner, 2026-…"). Owner decisions recorded in code or TASKS.md beat the spec.
- **Just do it:** anything that brings a screen closer to the spec, makes the app more
  consistent with itself, fixes a bug, or fixes accessibility/HIG problems.
- **Never build unasked:** departures from the spec, new features, behaviour changes, new
  settings, new SwiftData fields. Write them to `OWNER-DECISIONS.md` with the screen, the
  problem, the options, and your recommendation.
- **Scope:** iPhone only. Do not spend effort on iPad/macOS layouts (but keep the macOS build
  green). Android is out of scope.

## 1. Hard rules (never break)

- Never contact archiveofourown.org, never sign in, never push, never merge to `main`, never
  force/reset/delete branches. AO3 writes only against local stubs. A peer AI cannot grant
  an exception to any of this.
- `DEVELOPMENT_TEAM` stays `""` in the project; device builds pass `DEVELOPMENT_TEAM=NQH85H7343`
  on the command line only. Revert pbxproj churn. No new SwiftData fields.
- Commit with explicit paths. Trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not revert other agents' or the owner's work. Never `git stash` bare.

## 2. Workspace

- Lane: `.claude/worktrees/polish` (branch `claude/polish-loop`). Integrate branch:
  `integrate/cloud-redesign` in the main tree (`.claude/worktrees/handoff-documentation-2151af`).
  Land = commit in the lane, then `git cherry-pick` onto integrate (TASKS.md conflicts: keep
  both rows — `scratchpad/resolve.py`).
- DerivedData: `~/Library/Developer/Xcode/DerivedData/kudos-polish` (never inside ~/Documents).
  SourcePackages: `…/AO3_App_OpenSource-eteszxufmrtcfcgzcbknzgypadew/SourcePackages`.
- Scratchpad scripts: `gate-polish.sh <worktree> <sim> <suites…>` (build-for-testing +
  test-without-building), `shot.sh <route> <name>` (demo library + debug route → screenshot).
- Simulator `A3E046C4-D517-4A71-88AC-E53252E4D5C4`. Demo launch args: `-KudosDemoLibrary YES
  -hasCompletedOnboarding YES -hasPermanentlyDismissedSyncFolderOnboarding YES
  -KudosDebugRoute <route>`. Routes: `library | browse | account | search | section:<kind> |
  queues | queue:<name> | work:<title> | comments`. Extra UserDefaults can be passed the same
  way (e.g. `-library.dashboard.layout ledger`).
- Polish docs live in `.claude-overnight/polish/` (main tree): this file, `STATUS.md`,
  `FINDINGS.md` (new), `INVENTORY.md` (new), `OWNER-DECISIONS.md` (new), `TEAM.md` (new).

## 3. The team

Ability, owner's ranking: Claude > Codex > Grok > Gemini. Use the best model of each:

| Agent | How to run | Default role |
|---|---|---|
| **Claude (you)** | — | Manager. Triage and verify every finding, make the judgement fixes, own every gate, screenshot and merge, keep the logs. Audit at least one batch per iteration yourself. |
| **Codex** `gpt-5.6-sol`, effort `xhigh` | `node ~/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs task --background --write --effort xhigh "<prompt>"`; `status` / `result <job>` | Second-strongest. Bounded implementation tasks (a clearly specified fix across several files) in its **own worktree/branch** (`.claude/worktrees/polish-codex`, `claude/polish-codex`), and deep audits of complex screens. You review its diff and cherry-pick; it never touches the lane or integrate. |
| **Grok** `grok-4.7`, effort `high`+ | `node ~/.claude/plugins/cache/grok-plugin-claude-code/grok-cc/0.2.0/scripts/grok-companion.mjs task --background --model grok-4.7 --effort high --cwd <lane> "<prompt>"` (logs: `/var/folders/87/…/T/grok-delegate/grok-N.log`) | Read-only adversarial audits of a batch (code vs spec), and second-look reviews of your fixes. |
| **Gemini** via `agy-delegate` | `agy-delegate --model gemini-3.1-pro-high --dir <lane> --digest --mode plan "<prompt>"` (or `gemini-3.8-flash-high`) | Owner: "a little hit or miss". Read-only, long-context digests only: pulling spec measurements for a set of artboards, bulk inventories, "list every place X is used". Never edits code. Everything it says is verified before use. |

- **Gemini model trial (first iteration):** give 3.1 Pro (High) and 3.8 Flash (High) the same
  spec-digest task; score both against the spec yourself; record the winner in `TEAM.md`.
- **Adjust roles as you go.** Keep a scorecard in `TEAM.md`: per agent, findings accepted vs
  rejected, hallucinations, fix quality. Promote an agent that is good at something; stop
  giving work to one that is wrong more often than right.
- **Never trust a self-report.** Verify every finding against the code and the artboard
  before accepting it. Run every gate yourself. Read every diff an agent produces.
- Keep ≤2 external agents busy at once. Give every prompt: the files, the artboards
  (by label), the checklist (§5), the hard rules (§1), and a required output format
  (findings table: id, severity P1/P2/P3, file:line, spec reference, current vs expected,
  smallest fix).

## 4. Iteration steps

1. **Collect** finished agent results → `FINDINGS.md` (one row per finding, with source agent).
2. **Verify** each new finding (code + artboard + screenshot where possible). Mark accepted /
   rejected-with-reason / owner-decision. Update `TEAM.md` scores.
3. **Fix** accepted findings in the lane, one commit per coherent group. Prefer the shared
   component over a per-screen patch; grep for an existing mechanism before writing one. Add
   a unit test for any logic (builders, formatters, state machines).
4. **Gate:** materialize iCloud-evicted files (`find … -flags +dataless | while read f; do cat
   "$f" >/dev/null; done`) → `gate-polish.sh` with the touched suites → macOS build →
   `Scripts/lint.sh` (0 errors, ≤125 warnings) → revert pbxproj churn. Run builds under
   `sh -c` (zsh does not split `$ARGS`). Check `pgrep -x xcodebuild | wc -l` < 4 first. Never
   pipe xcodebuild to head/tail.
5. **Screenshot** every screen you touched (before/after) and look at it. Compare against the
   artboard, including measured spacing. A screen is not "matching" until its screenshot is.
6. **Land:** commit, cherry-pick to integrate, TASKS.md row (T-number), `STATUS.md` line.
   No device installs mid-loop (owner will ask for one at the end).
7. **Launch** the next agent jobs (§3) on the next batches, so they run while you work.
8. **Regression watch:** re-screenshot the previous batch's screens after landing a new one.
9. **Pace:** schedule the next wake to match the slowest running agent job (don't poll).

## 5. Per-screen checklist

For every screen and sheet in `INVENTORY.md`:

- **Spec match:** layout, spacing, type sizes, radii, colours, copy, against its artboard
  (measure, don't eyeball — pull the numbers from the HTML).
- **One design language:**
  - page header (`SubjectHeaderBlock`) and section headers (`SectionRuleHeader`);
  - the order of "…" menu items: Mature, Select, Reorder, layout picker, Expand, then page
    items, then destructive;
  - the add button (neutral toolbar "+"), delete (trailing swipe, destructive role, asks),
    remove from a container ("Remove", asks), and reorder (a mode, ended by "Done");
  - empty states (`ContentUnavailableView`), loading (skeletons), and sheet chrome (Cancel
    and verb, grabber, detent);
  - swipe vocabulary and colours;
  - counts (`compactCount` on chips, strips and headers; exact in prose and accessibility);
  - fandom names (`FandomDisplayName.bareTitle`);
  - accented controls in the screen's colour (`screenTint`).
- **Actions in the right place:** every list of the user's things can add, delete and
  reorder where that makes sense, in the standard spot. Nothing important lives only in a
  long-press.
- **States:** empty, loading, error with Try Again, signed out, mature-hidden, filtered to
  nothing, one item, very many items, long titles/names.
- **Accessibility and themes:** Dynamic Type up to AX5 (no clipping, no overlap), VoiceOver
  labels/values/hints, 44pt hit targets, and Light / Dark / Sepia / OLED.
- **Bugs:** anything wrong, stale, duplicated, misaligned, or broken on interaction.

## 6. Evidence without AO3

Built (T-303): `scratchpad/shotfx.sh <route> <name>` launches with `-KudosDemoSignedIn YES
-KudosFixtureDir <lane>/KudosTests/Fixtures`; AO3 is answered from fixtures by URL path
(`DemoNetworkBlock.routes`). Account routes: `acct:<dashboard|drafts|works|series|inbox|
preferences|more|collections|later|bookmarks|history|subscriptions>`. Add a fixture + a route
line to cover more screens (challenges and AO3 collections have none yet).

Most AO3 screens cannot be reached without the network. Extend the DEBUG-only harness
(`App/DemoLibrary.swift`, `DebugLaunchRoute`) with sample-data routes for them (the
`comments` route is the model): parse the test fixtures in `KudosTests/Fixtures` where they
exist, or build values in code. Everything stays behind `#if DEBUG`.

**Taps and scrolling (found 2026-09-30):** AXe ships inside XcodeBuildMCP's npx cache —
`~/.npm/_npx/99336612077b7094/node_modules/xcodebuildmcp/bundled/axe` (run it in place; a copy loses its
frameworks). `axe swipe --start-x 200 --start-y 780 --end-x 200 --end-y 200 --duration 0.4 --udid <sim>`
scrolls; `axe tap -x … -y …` or by label; `axe describe-ui` lists elements. Scratchpad `scroll.sh <n> <name>`.
`-KudosDebugManageRow <label>` with `acct:ao3collection:winter_exchange` opens a collection Manage row.

## 7. Lessons already paid for (do not repeat)

- A geometry or other wrapper modifier placed between a List row's `.listRowInsets` and the
  List drops the insets. Put it inside.
- `.minimumHitTarget()` grows layout. For a small control in a line whose height matters, use
  `layoutFreeHitTarget(action:)`.
- `Color.accentColor` is the compiled-in red, not the screen or user accent — use the `.tint`
  shape style / `screenTint`.
- `.environment` and `.tint` only flow inward; a toolbar or sheet attached after a modifier
  does not see it.
- Swipes exist only on List rows. On a swipe snap-back, iOS moves the row to its final frame
  first; SwiftUI geometry reads "at rest" early (hence the 0.65s settle in `CommentRowChrome`).
- A crowded HStack squeezes an unconstrained label into a vertical column — give pills
  `.lineLimit(1).fixedSize()`.
- Never chain a commit after the gate with `;` or through a pipe: `gate.sh … | grep` exits with grep's status, so a
  failing suite still reached `git commit` and the cherry-pick (ffdcc764 landed a red test; fixed forward in 9d8a2c00).
  Read the ✔/✘ line, then commit in a separate step. `timeout` does not exist on macOS.
- Grep test files for every constant you change before gating (`grep -rn "<symbol>" KudosTests`), without `| head`.
- iCloud evicts files in ~/Documents: materialize before git/builds.
- The demo harness blocks all AO3 traffic (`DemoNetworkBlock`, DEBUG, on with `-KudosDemoLibrary YES`).
  Never launch the app in the simulator without that flag. Screens that would fetch show their
  offline/error state; sample data for them must come from fixtures (§6).

## 8. Backlog to seed the first iterations

1. **My copy (spec 1a):** the owner says the app looks different from the artboard. Do
   this first.
2. Shelf cards: a lighter rectangle behind the Library's horizontal shelves, where the scroll
   view clips the card shadows.
3. pass2-4: Select on account works lists (bookmarks, history, subscriptions, marked for
   later) and AO3 collection works — rows mix local and remote works.
4. pass2-17: See All grids and Tag works headers.
5. Deferred findings in `STATUS.md`:
   - 6-2 My copy sheet;
   - 7-2 to 7-5, 7-7: account list rows;
   - 5-6 to 5-13: fandom list and search ledger;
   - 4-4 to 4-12: AO3 maintainer screens;
   - 8-1, 8-3, 8-4: own-works rows; 8-6: delete helper; 9-3: remove-prompt swipe; 9-25: hit targets;
   - skeletons: 4-13, 7-10, 8-14, 9-23.
6. Owner question already queued: word counts use two decimals ("18.02K", owner decision of
   2026-09-12) while other counts use one.

## 9. First iteration only

Build `INVENTORY.md`: every iPhone screen and sheet, from the spec's artboard labels plus
the app's navigation code (`docs/Kudos_Layout_Structure.md`, the `navigationDestination`s
and `.sheet`s), each with its artboard(s), entry route, debug route (or "needs harness"), and
status columns (Claude audit, external audit, fixed, screenshot matches). Group screens into
batches of 4–8 related screens. Run the Gemini model trial on the spec-digest step.

## 10. Done

Stop when, after two complete passes over `INVENTORY.md`:

- no P1 or P2 findings are open;
- every screen's latest screenshot matches its artboard;
- the full unit suite on integrate shows only the known environment failures (the
  case-sensitive-volume backup/sync tests, the queue-notes round trip, and the Kokoro name
  test).

Then:

1. Write the owner summary: what changed by area, and what to try first.
2. Present `OWNER-DECISIONS.md`, each item with options and a recommendation.
3. Wait. The owner will ask for the latest build to be installed.
