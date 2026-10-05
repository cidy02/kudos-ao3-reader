# Brief 3bc: Writing foundations 2, the recovery store and AO3's word count (no screen)

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess (put **every**
open question in your final summary, not only the first). Write
`docs/android-port/briefs/3bc-result.md` as you go.

Read first: `docs/WRITING_EDITOR_ARCHITECTURE.md` §3.6 (word counting), §5.2 (invariants), §8
(checkpoints, auto-save and recovery: **normative**), §10.2 (Android) and §12.2 (what must be
identical on both platforms).

## Why

Before Android lets anyone type a chapter, what they type must survive a crash, a failed save
and a lost session. The design document fixes how: checkpoints on a schedule, written to disk
in order, in a layout and with a key derivation that are **the same on both platforms**. And
the word count a writer sees must be AO3's own count. This brief builds both as pure code with
no screen, so that the editor brief that follows only has to call them.

## iOS reference

Recovery and checkpoints: `Features/Writing/WritingCheckpoint.swift`
(`WritingCheckpointPolicy`, `WritingCheckpointScheduler`), `WritingRecoveryWriter`,
`WritingTextRecovery` and whatever they use (find them), and their tests in `KudosTests/`.
Word count: `Models/AO3WordCounter.swift`, `WritingWordCount`, and their tests.

Start the result with the inventory, read from the code and checked against the document
(where the code and the document disagree, **say so at the top**, then follow iOS's code):

1. The checkpoint policy's numbers and every event besides the timer that forces a checkpoint.
2. What one recovery copy holds, field by field; the file's name and how its key is derived;
   the directory layout; how writes are ordered; how copies are pruned and when; what is read
   on opening a field and how a newer copy is offered; what is removed after a successful Save
   or Post; whether copies are in device backups on iOS.
3. AO3's word count as iOS implements it, step by step, with each script range and rule.

## Build

- `writing/recovery/` (or beside `network/ao3/writing/` if brief 3bb's package exists: look):
  the checkpoint policy and scheduler (clock passed in; no wall-clock reads in the logic), the
  recovery writer (one ordered writer on `Dispatchers.IO.limitedParallelism(1)`, as §10.2
  says), the store with §8.3's layout and key derivation and §8.4's pruning, and §8.5's
  reading side. Files live in app-private storage. **They are not part of Kudos's backup or
  sync** (no change to the backup format, and no Room table); say whether Android's own device
  backup would include that directory today and what the document's OD4 says about it, and
  change nothing about device backup.
- AO3's word counter, as a pure function, with iOS's rules exactly.
- No screen, no route, no network. Nothing in the app calls these yet except tests.

## Tests

- **iOS's own test cases, ported as they are, with their names**, for the policy, the
  scheduler, the writer's ordering, the store, pruning, reading on open, and the word counter.
  A count that differs from iOS's on any of iOS's vectors is a failure of this brief.
- The file format: a recovery copy written by this code, byte for byte what iOS writes for the
  same input (take iOS's expected bytes or JSON from its tests or its encoder; if iOS's format
  depends on something not reproducible off the device, say exactly what).
- Ordering under load: a hundred checkpoints queued out of order arrive on disk in checkpoint
  order, and the last one wins.
- A copy that cannot be read is skipped without failing the list (iOS does this: find its
  test).
- Process death: what is on disk after the writer is cancelled mid-queue is a complete copy or
  the previous one, never a partial file.
