# Handoff: finish the Kudos redesign in a cloud session

You are picking up a design job from a local Claude Code session that stopped at a usage limit on 2026-10-26.
The job is a redesign of Kudos (the AO3 reader app in this repo) on a Design canvas: an app that looks and feels
like Apple designed and shipped it, plus a version for the iPhone Duo (cover display, unfolded, Book pose).
It is a design job. Don't change app code.

## What the owner wants (read this first)

In the owner's words: *"We've put a lot of work into the current version of the app, and we've already been through
one redesign. I don't want to throw that work away. I'm chasing a polished version I can't seem to find. It needs
to feel more like a native Apple app. AO3 is all fanworks, so some things are limited: works have no covers, and
that limits the design options. I want the app to feel polished and coherent, but I'm stuck. It feels a little too
one-dimensional at the moment."*

What that means for you:

- **Evolve, don't replace.** Today's app is the result of a full redesign, and most of its parts are right. Before
  you draw anything, read `docs/PROJECT_PHILOSOPHY.md`, `docs/REDESIGN_DECISIONS.md` (binding unless the owner
  overrides one) and the "What to keep" list in `notes/critique-report.md`: the fandom wash, kicker and card colours
  as identity, the full AO3 metadata density, Home's single left edge, the progress ring and Resume hero, the
  "Tap to reveal" blur, the queue's segmented progress bar. Every board should be recognisably Kudos.
- **The gap is polish and coherence, not features.** The critique names three causes: the app draws its own
  navigation instead of using the system's, colour, type and boxes have no rules, so everything is equally loud,
  and the reading life is invisible. Fix those. Don't add new things for the sake of it.
- **"One-dimensional" is the problem to solve.** Our reading of it: every surface is tinted, boxed and capitalised
  at the same volume, so nothing is in front of anything else, and every work is drawn as the same card, so a shelf
  of ten fics looks like ten copies of one shape. Apple's apps get depth from hierarchy: chrome that recedes,
  content that leads, sections with different shapes, and moments that matter. Check that reading with the owner.
- **No covers is a constraint to design for, not around.** Don't fake cover art. What every fic does have is its
  fandom, its words, its tags, its shape (length, chapters, WIP cadence) and the reader's history with it. Places
  to look: Apple Music's generated playlist art and Apple Books' plain-title covers (the `CoverCard` text variant
  already exists); the passage where you stopped as the hero's "cover" (critique finding); a work's shape drawn as
  data, the way Fitness and Health make rings and charts the imagery; varied section shapes on Home the way Music
  and the App Store do it; the end-of-work and kudos moments. These are starting points, not answers.

## Where things are

- **Canvas:** https://claude.ai/artifact/YDoKqygRYFNBhAch47Bmux (made from the Design Artifact type). Read it
  first with the Artifact tool (`action: "read"`). The read brings the type's instructions; follow them.
- **This folder** (`Design/redesign/`) is the canvas's local root: `project/` holds every board (`*.dc.html`)
  and `canvas.json`. The board files here match what is published, except for the ones listed under "Not
  published yet".
- **LEDGER.md**: the plan, the owner's rules and the queue. Work from it and tick items as you finish them.
- **FORMAT.md**: the `.dc.html` format rules (the type's instructions are the authority if they differ).
- **notes/**: `critique-report.md` (35 verified findings about today's app), `duo-code-survey.md` (how the code
  handles the fold today), `board-survey.md` (shared parts and conventions of the existing boards), and
  `duo-writer-reports.md` (what each Duo board's writer said it drew).

Publish a board like this, one file per call, then the next:

```
Artifact { url: "https://claude.ai/artifact/YDoKqygRYFNBhAch47Bmux",
           root: "<repo>/Design/redesign",
           file_path: "<repo>/Design/redesign/project/<Board>.dc.html" }
```

Send `project/canvas.json` the same way, but only when you add or move boards. Read the published one back first
(`action: "read"`, `path: "project/canvas.json"`), because the owner may have edited it on the canvas.

**If this session has no Artifact tool, or the read fails:** stop and tell the owner. Don't redesign blind. You can
still commit board files here, and a local session can publish them later.

## You can't take screenshots. Use these instead

There is no Mac, simulator or device here. The owner's rules already say not to check boards by screenshot unless
the owner asks. Everything you need to see the current app is in `shots/` (JPEG, half size):

| Folder | What it is |
|---|---|
| `shots/iphone/` | 143 screens of today's iPhone app (iPhone 17 Pro, light, demo library), from the iOS/Android parity run on 2026-10-25, build `1e5d3d44` (the tip of `claude/iphone-duo`). Name key: `hsec_` Home section, `sec_` Library section, `s_` a Settings page, `ch` challenge, `col` collection. |
| `shots/iphone-variants/` | home, workdetail, reader, library, sec_reading in `dark`, `sepia`, `oled` and `big` (AX5 large text). For queue items 9 and 11. |
| `shots/android/` | home, workdetail, reader, library, account on today's Android app (Material 3). For item 10. |
| `shots/duo-cover/` | 24 screens on the iPhone Duo **cover** display (466×678, tab rail on the right), light, from 2026-10-24 (a slightly older build). |
| `shots/evidence/` | The 18 shots behind the critique, with `INDEX.md`. 09 = Duo cover Account, 10 = Duo inner Home, 11 = wide layout with sidebar. |

There are no screenshots of the unfolded or Book poses beyond evidence 10. For those, go by `notes/duo-code-survey.md`
and the code (`kudos-ao3-reader/UIComponents/AdaptiveContentRegions.swift`, `WideLayout.swift`,
`Features/Home/HomeView.swift`). Reading the code is fine. Changing it is not. The survey was taken from a local
working tree that also had uncommitted Duo work (`LocalNavigationHost.swift`, the Library/Account/Settings sidebar
lists). Those files aren't in this branch, so for those parts the survey is your only source.

## Step 0: help the owner get unstuck (before the Duo boards)

The owner is stuck on direction, so don't polish 12 more boards in a direction they haven't confirmed. First, make
one board, `Direction.dc.html`, on its own canvas page: Home and Work Detail in two or three directions. Each
direction is an evolution of today's app (same parts, same density), and each takes a different answer to
"depth without covers". Put a short caption under each saying what changed and which Apple app it borrows from.
Publish it, ask the owner to pick (or mix), and record the choice in LEDGER.md under "Notes / decisions". Then
carry the chosen direction into everything below, including the boards already written.

## Not published yet

Queue item 8, the iPhone Duo boards. A background workflow wrote these, but every reviewer hit the usage limit,
so **none of them have been reviewed, and none are published**:

- Rewritten locally: Duo-Cover-Home, Duo-Book-Reader (moved onto the shared components).
- New, written: Duo-Cover-Reader, Duo-Open-Home, Duo-Open-Account, Duo-Open-Settings, Duo-Open-Reader,
  Duo-Book-Comments, Duo-Book-Home, Duo-Portrait-Browse.
- **Duo-Open-WorkDetail**: the file is there, but its writer errored before reporting. Check it carefully first.
- **Duo-Open-Search**: not written.
- Also local only: `Flow-Duo.dc.html` (the Duo storyboard), an updated `Coverage.dc.html` (14 Duo rows, a
  "Key journeys" section, frame 8000 px tall) and `canvas.json` (entries for the new boards).

For each Duo board: review it against the north star in LEDGER.md and the fold behaviour in the survey, fix it,
publish it, then do the next one. After that, publish `canvas.json` (merged with the published copy), then
Flow-Duo, then Coverage. Then tick item 8 in the ledger.

After item 8, go on down the queue: 6d (rule sweep, including "Save for Later" → "Want to Read" on Work-Actions,
Library, Main, States-Feedback), 9 (Dark/Sepia), 10 (Android), 11 (AX5), 12 (final pass and the morning note).

## Working rules for the cloud

- Each iteration, check comments first: `ArtifactComments` on the canvas → act → reply → resolve.
- Budget: the owner has about $99 of cloud credits for all of this. Work one board at a time in this session.
  Don't run Workflow fan-outs or parallel subagents. The last fan-out (24 agents) used 2.5M tokens.
- Git: commit only inside `Design/redesign/`, and push this branch after each board or two so nothing is lost
  if the session ends. Never push to `main`, never force-push, and never merge this folder into an app branch.
  The screenshots are here for the redesign, not the app.
- Questions for the owner are listed in LEDGER.md under item 1 and item 6. Ask them in the chat. Don't guess
  answers into the boards.
