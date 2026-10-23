# Brief 3gy (Android): make 3gx's sixteen held tests pass, or fix what they found

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex2`, branch `android/agent-codex2-3gy`,
from the lane's 3gx landing). Do not commit, push, switch branches, sign in, contact archiveofourown.org,
or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Write
`docs/android-port/briefs/3gy-result.md` first and fill it as you go.

3gx landed. Sixteen of its new tests failed when Claude ran them and are marked
`@Ignore("3gx, held for 3gy: <the failure>")` (`grep -rn '@Ignore("3gx' android/app/src/test`). For each:
read the failure, decide whether the **test** is wrong (it looks for the wrong text, needs a scroll, a
larger window, an idle wait, a stable list, or the composable outside a dialog window) or the **app** is
wrong, fix that, remove the `@Ignore`, and say which in the result. Never weaken an assertion just to
pass: if a check can't work under Robolectric, test the same rule another way and say how. Each fixed
test must still fail with its app change reverted; say what it does then.

What Claude already knows:
- `TagSheetParityTest` (three cases) runs out of memory: the AlertDialog's window is re-measured without
  end under Robolectric (`ViewRootImpl.measureHierarchy` → `performTraversals`, 83 s of CPU in 98 s).
  The same dialog opens and works on the emulator. Test `QueueTagEditDialog`'s content outside an
  `AlertDialog` (extract the body into a composable the dialog and the test both use), or otherwise
  avoid the dialog window.
- `LibraryForms3gxTest.collectionPickerShowsNewestCreatedFirst`: Compose never goes idle (likely the
  dialog window again, or the membership load's spinner never finishing under Robolectric). The dialog
  works on the emulator.
- `FandomFilterSheetParityTest.showTagsStaysVisible…`: on the emulator at 2.0× the pinned "Show N tags"
  stays after scrolling, so check the test's own steps ("Show 0 tags" may never be the right count).
- The others are listed in each `@Ignore`'s reason.
