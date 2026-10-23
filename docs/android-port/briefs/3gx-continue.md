# Brief 3gx, continued (Android)

Your run of brief 3gx (`docs/android-port/briefs/3gx-a82b-android.md`, in this worktree) stopped at
your usage limit. Its edits are still here: `git diff --stat` shows 58 changed files, and
`docs/android-port/briefs/3gx-result.md` is still the "in progress" stub.

Same rules as the brief: **write code in this worktree only (`/Users/cidy02/kudos-agent-codex`,
branch `android/agent-codex-3gx`); do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests); do not edit `TASKS.md`.**

1. Read the brief again, then your own diff. Check each change you already made against its item
   (and against the iOS reference); fix anything half-done.
2. Finish the items you had not reached.
3. Write `docs/android-port/briefs/3gx-result.md` in full: per item `path:line`, what changed, and
   per test what it does with its change reverted; "Owner questions"; "iOS side" (A84a items where
   iOS is the side missing something); and anything you skipped and why. Say why
   `android/app/build.gradle.kts` changed (a `GIT_BRANCH` BuildConfig field) and which item needs it.
