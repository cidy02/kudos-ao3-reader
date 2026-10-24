# Duo5c — take the resize hold-and-restore out of T-449; keep what is plainly right

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios2`, branch `claude/agent-ios-duo5c` (from the iOS lane's
`64979c71`: T-449 plus the T-450 TASKS row). iOS only.

## Why (Claude-CLI's decision, 2026-10-24; the owner gave Claude the Duo calls)

T-449 added a layer that, after a size change, holds the reading locator, swallows same-chapter location
callbacks and later restores the held locator itself. Two adversarial reviews found it loses or mis-saves
the position in many ways (R449: `docs/android-port/briefs/R449-result.md`; R450, on the Duo5b fix:
`docs/android-port/briefs/R450-result.md`, five P1s): it fights Readium, which already keeps the position
through a reflow (its own pending-location scroll, native paging and links all bypass the layer). Usability
first: **remove the layer and let Readium own the position through a resize**, as before T-449. Keep the parts
of T-449 that are plainly right.

## Keep

1. The side safe areas: text, the loading skeleton and every reader control padded to the host's safe width;
   the page background full-bleed (`ReadiumReaderView.swift`'s padding, `ReaderPageBoxGeometry.horizontalInsets`).
2. The host-based page box (`ReaderPageBoxGeometry`, seeded from and refreshed by the host view's size and
   insets, not `UIScreen`), with its status-bar/chrome protection.
3. After a settled size change: clear the visual page metrics and run the existing scheduled remeasure, so
   "page X of N" and the seek scale fit the new size (Duo3 finding 16). Ordinary page turns publish at once
   (T-449 round 2's fix for unready bars rearming on a same-href settle stays). The guard's bounded
   last-attempt fallback stays.
4. The DEBUG `-KudosDebugRotate` hook.

## Remove

- The resize locator hold (`pageBoxResizeLocator` and everything that captures, checks or clears it), the
  same-href callback gate that discards location updates during a resize, the app's own restore task
  (`go(to:)` of a held locator, its retries, `markFirstPagePresentedIfNeeded` from it), and the flags that
  exist only for the hold (`hasReceivedNavigatorLocator`/`hasMeasuredPageBox` if nothing else needs them).
- Tests that assert the hold; keep and adapt the ones for the page box, the remeasure, page turns, and add
  one that proves a same-href location update *during* a resize is accepted (it reaches `currentLocator` and
  persistence as before T-449), and one that no restore `go(to:)` is issued by a resize.

After this, the reader's position handling on a resize must be exactly what it was before T-449
(`git show 97187d9a^:kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift` is the reference for the
location/persistence path); say in the result where it differs and why.

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds, gates and checks on the
  simulator and the Duo.
- Smallest diff that does it; no new UI.

## Output

`docs/android-port/briefs/Duo5c-result.md`, written first: what was removed and kept (file:line), the location
path compared with before T-449, the tests and how they fail when reverted, simulator steps.
