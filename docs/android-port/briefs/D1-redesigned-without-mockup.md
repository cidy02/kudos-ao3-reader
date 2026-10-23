# Brief D1 (documentation): finish REDESIGNED-WITHOUT-MOCKUP.md

**Edit exactly one file: `docs/android-port/REDESIGNED-WITHOUT-MOCKUP.md` in this worktree
(`/Users/cidy02/kudos-agent-opus`).** Read anything; change no code; do not commit, push, switch
branches, run builds, sign in, or contact archiveofourown.org. Write plainly, for the owner.

The owner (2026-10-20): *"if there are any screens that are not redesigned in the mockup, feel free
to do a best effort redesign and document it. the goal is visual and UX parity with no lost
features or information"* and *"document in a separate .md any screens without a mockup that you
redesign"*. The file's own header states the rules for an entry. Its table lists screens with no
artboard, several still "to look at", and its "Redesigned screens" section says "(none yet)". The
Android port has since matched many of those screens to the iPhone's; the file was never updated.

Sources (read, do not change):
- The artboard index: `/Users/cidy02/kudos-ios-integrate/.claude-overnight/polish/artboards.tsv`
  (86 artboards → iOS files) and `INVENTORY.md` beside it. A screen with no artboard row is a
  screen without a mockup.
- Every iOS screen and its Android counterpart: `docs/android-port/audits/A81-result.md`.
- What changed and why: `docs/android-port/DECISIONS.md`, the Android lane's history
  (`git -C /Users/cidy02/kudos-android-lane log --oneline -- <file>` and `git show` on the commits
  that touched a screen), and the side-by-side audits `docs/android-port/audits/A69*` to `A80*`
  (their "result" files say what was compared, in which themes, and what was fixed).
- The screenshots, if you want to look: `/Users/cidy02/kudos-tools/pairs/tiles*/<name>.png`
  (iPhone row above Android row; Dark, Light, Sepia, OLED, largest text).

Do this:
1. Make the table complete: every screen with no artboard, on both apps (use A81's 146 screens
   against the artboard index), with its status: **matched** (compared side by side, name the
   audit), **redesigned** (an entry below), **A82 pending** (one of the 70 screens being compared
   now, listed in `docs/android-port/audits/A82-shots.md`), or **not compared** with the reason.
2. Under "Redesigned screens", one entry per screen Android restyled without a mockup (whether it
   followed the iPhone's look or both apps got the same new design), in the header's format: what
   it was, what it is now, the iOS screen it matches, what was kept, the commit(s), and how it was
   seen (audit, themes, text sizes). Cite commits and audits; do not invent any. Where the history
   does not say, write "not recorded".
3. At the top, a three-line summary: how many screens have no mockup, how many are matched,
   redesigned, pending and not compared.
