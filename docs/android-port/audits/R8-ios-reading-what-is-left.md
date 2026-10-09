# R8: what is still unbuilt, read in full (four screens)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R8-result.md`. No helper scripts left behind.

iOS is at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). Android is in this
worktree under `android/app/src/main/java/io/github/cidy02/kudos/`.

Each of the four below will be built on Android from what you write, by someone who will read
iOS's code again to check you. So: quote, with `path:line`; never write from memory; where you
are not sure, say "not found" or "not sure", never a guess. For **each** screen write:

1. **What is on screen**: every string, word for word and in order, with its `path:line` and
   the condition under which it appears (who sees it; which state). Every control and what it
   opens or does. Loading, empty, failed and signed-out states and their words.
2. **What it reads and writes**: quote the Swift that builds each request (the address, every
   field name and value and where the value comes from, when it is made, what stops it being
   made twice), what counts as AO3's confirmation and what as a refusal (quote the code), and
   each message shown for each verdict. Count the requests for one opening.
3. **What Android has today**: the file and function that would open this screen, and what it
   does instead (opens the in-app browser? shows the value and opens nothing? nothing at all?).
   Search before saying "nothing": name the files you looked in.
4. **What `docs/AO3_NETWORKING_POLICY.md` says**: quote each rule that allows or limits a read
   or write here.

The four:

- **Challenge settings, the edit form** (a gift exchange's and a prompt meme's): everything a
  moderator can change and save. Start from `Features/Challenges/` (the settings view, its
  edit mode or edit sheet) and the service that saves it. Android has the read-only screen
  (`account/AO3ChallengeSettingsScreen.kt`, brief `briefs/3ba-result.md`).
- **A challenge's matching and its moderator actions** (generate matches, send assignments,
  purge, the potential matches list, a single match's edit), if iOS has them; say exactly
  which exist on iOS and which do not.
- **Support** (`Features/Support/`): every screen in it, what each links to, and anything it
  reads from the network or the store.
- **Onboarding beyond the first run** (`Features/Onboarding/`): every screen and sheet not
  already described in `briefs/3ax-result.md` (read it first, with its landing note), and
  when each is shown.

End with a table: screen, iOS file, lines of Swift, requests per opening, writes, Android
today. If you run short of time, finish the screens in the order above and say where you
stopped: a complete first screen is worth more than four half-read ones.
