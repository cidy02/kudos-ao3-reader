# Audit A4: iOS, every write to AO3 and every read that repeats

**Read-only.** Change no file except the one result file. Do not build, commit, push, switch
branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A4-result.md` (in this worktree).

The code to audit is the iOS app at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (Swift;
read-only). The rule book is `/Users/cidy02/kudos-ios-polish/docs/AO3_NETWORKING_POLICY.md`
(its "must not implement" list is binding) with
`/Users/cidy02/kudos-ios-polish/docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

You are hunting for **bugs**, not style. Four real ones were found in this code in the last
three days by reading it closely; they show what to look for:

- a "best-effort" read that tested only whether a value had arrived, so a lookup that could
  not succeed was repeated with every page and every action (`PromptMemeView`, fixed);
- a screen that reads every page of three lists, uncapped, to show three numbers
  (`ChallengeSettingsView` with `allChallengeAssignments`: open, an owner question);
- a form encoder that leaves out fields AO3's page served (`AO3WorkForm.parameters`: open);
- a preview that dropped text outside a block tag (`WritingBufferPreview`, fixed).

## What to read

1. **Every write**: `Services/AO3WriteActions.swift`, `AO3WorkActions.swift`,
   `AO3ChallengeActions.swift`, `AO3CollectionActions.swift`, and every other function that
   builds a POST (find them: `submitWrite`, `writeRequest`, `fetchCSRFPage`, `httpMethod`).
   For each: is the token fresh and from the right page; can the request be sent twice (a
   double tap, a retry, a task restarted by SwiftUI, a refresh during flight); is a refusal
   told apart from success, and an unconfirmed reply from both; does the screen change before
   AO3 confirms; is anything sent the user did not ask to send; does a failure lose what the
   user typed.
2. **Every read made in a loop or more than once**: `while`, `for page in`, `loadNext`,
   `all…` functions, `.task`, `.onAppear`, `.refreshable`, `.onChange`, timers, and any read
   guarded by "if I don't have it yet". For each: is it capped; is it on the policy's list;
   can it repeat without a user action; is it made for a viewer AO3 will refuse; does it
   survive a session change.
3. **The writing editor's data path**: `Features/Writing/` and `Services/WritingTextRecovery.swift`,
   `WritingRecoveryWriter.swift`: can typed text be lost (leaving, backgrounding, a crash, a
   restore, a session change, two editors on one field), or a stale copy overwrite a newer.
4. **The challenge and collection screens** under `Features/Challenges/` and
   `Features/Account/AO3Collection*`: state that outlives its screen, a result applied to the
   wrong collection after a fast switch, a destructive action without a confirmation.

## What counts as a finding

A concrete fault with a failing case: P1 loses data or sends something wrong to AO3; P2 a
wrong behaviour a user meets or a read the policy does not allow; P3 the rest. Not findings:
style, naming, "could be simpler", anything a comment in the code says is deliberate **unless
the comment is wrong** (say why).

## The result file

A table first: id, severity, `path:line`, one-line statement. Then one section per finding:
the code quoted with `path:line`, **a concrete failing case** (the taps or state, what
happens, what should), the policy or invariant line it breaks if any, and the smallest fix.
Suspicions you could not confirm by reading go under "Unconfirmed" with what would confirm
them. End with what you did not read. Exact files and lines only: one wrong line makes the
report untrustworthy. Check a claim about a library or language rule before you rest a
finding on it (the last audit's one finding misdescribed a `trim`).
