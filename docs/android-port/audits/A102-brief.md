# A102: the verification pairs, judged adversarially (Claude-CLI)

The owner asked for Android parity's "Done" to be verified, not taken on trust, before any iPhone Duo work
(LIVING-PROMPT §0, owner 2026-10-24 21:38). Part 1 of Done: every §7 row ✅, with its pairs in Dark,
Light, Sepia, OLED and at the largest text. Most screens were last paired before many shared changes; 32
screens' newest Android shots were from 10-22. So every screen was shot again tonight on both phones'
current builds:
- **iPhone:** a clean worktree at polish `1e5d3d44`, without the staged Duo work.
- **Android:** the lane at `7b2f69f4` (code unchanged since).

That's 109 screens from `~/kudos-tools/pairs/list-final-all.txt` and the 14 Settings pages, five columns
each.

**Your job is to find what "Done" missed.** You declared Done at 08:05, so read every tile as if it hadn't
been judged before. A second judge (Claude-Code) reads them all independently, and the two results are
merged.

Rules:
- Read only. Write only `/Users/cidy02/kudos-agent-ios/docs/android-port/briefs/A102-cli-result.md`.
- No builds, no simulators, no git writes, no AO3.

Tiles go to `/Users/cidy02/kudos-tools/pairs/tiles-verify/<name>.png`, in batches as Android's shots
finish; Claude-Code messages you as each batch is ready. Each tile has the iPhone row on top and Android
below; the columns are Dark, Light, Sepia, OLED, then Sepia at the largest text. Raw shots are in
`/Users/cidy02/kudos-tools/pairs/shots/` (`i_` and `a_<name>_<column>.png`) for crops and pixel samples.

For each screen, give one verdict, with the column and the platform for everything you name:
- **match:** nothing different except decided differences and demo data;
- **minor:** a small visual or wording difference that loses nothing;
- **differs:** a missing or extra control, figure, line of text or state, a wrong colour family, cut text,
  or a layout that hides something;
- **capture problem:** a column showing the wrong screen, a spinner, "isn't responding", Home, or a blank.
  Say which, so only that column is re-shot.

Don't report what's decided: `docs/android-port/DECISIONS.md` (including D7, D8 and the round-3 entry),
A76's "Decided, not to report" list, and the "Decided, not changed" section of `audits/A88-triage.md`.
Also skip demo data (different works, counts or names) and owner question Q28 (card dates). When unsure
whether something is decided, report it and say so.

Write the counts at the top (match / minor / differs / capture problems), then the differs list, then
per-screen verdicts.
