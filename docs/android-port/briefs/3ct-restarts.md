# 3ct: what a restart of the screen does (Android)

Done 2026-10-12 by Claude, alone. Gate 2,624 (two new tests). Pictures: `shots/3ct/`.
A bug hunt, started from 3cr's lead. "Restart" here is Android destroying the activity and
building it again: on a change of configuration the app does not handle itself, and when
the reader returns to the app after its process was killed in the background.

## Found and fixed

1. **The app crashed on any restart with a work open in the reader.** Android rebuilds an
   activity's fragments itself, Readium's reader fragment has no empty constructor, and
   the rebuild threw: `Fragment$InstantiationException: Unable to instantiate fragment
   org.readium.r2.navigator.epub.EpubNavigatorFragment`. Seen on the emulator: a work open,
   `cmd uimode night yes` (what the phone does at sunset on a schedule), and the app was
   gone. The same path runs when a reader comes back to a work after the system has
   killed the app in the background.
   Fix: `ReaderFragmentRestore`, called either side of `super.onCreate` in `MainActivity`.
   Readium's own dummy factory stands in for the rebuild (it is what Readium provides for
   this) and the rebuilt fragment is removed at once; Compose adds the real one when the
   reader is drawn, as it always has. Tests: `ReaderFragmentRestoreTest` (the restart
   leaves nothing behind; without the guard it throws).
2. **What was being typed was lost when the phone switched to dark** (and on a text-size
   change, or a keyboard being connected). The screens keep what is being written in
   memory that a restart clears; the work form then read itself again from AO3. Seen: a
   draft's title typed into, `cmd uimode night yes`, the typing gone.
   Fix: the activity handles `uiMode`, `fontScale`, `keyboard` and `navigation` itself
   (`configChanges`), so none of them restarts it. Compose already redraws for each: the
   System theme follows the phone and the bars' icons flip, and text re-lays out at the
   new size. Locale is left to restart the activity, so every string is rebuilt.
3. **A file opened with Kudos was offered for import again after a restart.** `onCreate`
   offered the launching Intent's file every time, and a restart hands the same Intent
   back. It is offered on a fresh start only. From reading the code; not reproduced.

## Seen on the emulator after the fix

- A work open, the phone switched to dark: same process, the reader still on its page.
- A work open, Home, `am kill`, back to the app: a new process, no crash, the reader on
  the same page.
- A draft's title typed into, dark switch: the typing is there. Text size to 1.3× and back:
  the typing is there and the form re-lays out each time.
- Theme set to System: the phone to dark and back; the app follows without a restart.
- No crash record for the app in the log in any of these.

## Still lost, not fixed here

**What is typed into the work form is lost when the app is killed in the background**
(seen: typed, Home, `am kill`, back: the same draft's form, without the typing). A writer
who leaves for another app to copy text and comes back later can meet this. iOS keeps
recovery copies. Android has a recovery store for the editor's text (3bc); the form's
fields are not in it. Next.

## Not checked

- A hardware keyboard being connected (not reproducible on the emulator); it is the same
  kind of change as the two that were tried.
- A change of language while the app is open (it still restarts the activity; the reader
  goes through the guarded path, the same one as the return after `am kill`).
- Comments and Search with text typed in, through a dark switch (they are on the same
  activity, which no longer restarts).
