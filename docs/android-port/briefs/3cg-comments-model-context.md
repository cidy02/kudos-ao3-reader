# Brief 3cg: the comments model, one captured context (audit A32, items 1, 4, 5 and 8)

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle. Claude builds, tests and commits afterwards, so make what you write compile by
reading the real symbols you use, and say which claims need a test run. Write
`docs/android-port/briefs/3cg-result.md` as you go. Put every open question in your final
summary, not only the first.

**Android only, and only the files named here.** You reviewed Claude's fixes in
`docs/android-port/audits/A32-result.md` (read it again with its triage at the foot). Three of
those fixes were incomplete, each for the same reason: the model remembers a count or a name
where it needs to remember **what it was opened for and for whom**. Claude has patched this
model by hand three times (audits A28, A30, A32). Do it once, properly.

## Scope: exactly these

- `comments/CommentsViewModel.kt`: `openComposer`, `startReply`, `startEdit`, `saveDraft`,
  `submitComment` and its completion, `closeComposer`/cancel, `setTarget`, `setScope`, `load`
  (only where it keeps or drops the composer), `present` and `without`, `loadChaptersIfNeeded`
  and what it stores.
- `comments/CommentsScreen.kt`: how the model learns who the viewer is (today a username
  lambda, lines about 120 to 124) and the reader effect that calls `openOnChapter` (about 141
  to 147).
- `app/AppNavHost.kt`: only the lines that hand the viewer to the comments screen.
- Tests: `comments/CommentsViewModelDraftTest.kt` and a new test file if one is clearer.

**Do not change** any repository, any request, any verdict rule, any other screen, the comment
row or the composer sheet's layout, the demo network, or any string on screen. If a complete
fix seems to need one of those, stop and say so.

## What to build

1. **A composer context**, captured when a composer opens (new comment, reply or edit): the
   target it is for (work or chapter), the viewer's session (see 3), and its own generation.
   Every draft lookup, `saveDraft`, `submitComment` and submit completion uses the **captured**
   context, never "whatever is current now". Then:
   - a draft read that returns after the target or the viewer changed is dropped;
   - a target change (`setTarget`, the reader effect) while a composer is pending or open
     either closes it, saving its text to **its own** slot first, or leaves it bound to its
     original target: choose what iOS does (`Features/Comments/CommentsModel.swift`), say
     which, and test it;
   - a submit that succeeds after its sheet was dismissed and another composer opened clears
     **its own** draft slot and leaves the new composer and its text alone;
   - a same-target reload and a failed submit keep the composer, as now.
2. **`present`**: the comment asked for is put first only when it is proven absent from what the
   page will draw, checking the **whole** tree of ids, not the top level; nothing is prepended
   whose own id the page already draws; pruning a node the page has must not prune the
   comment asked for beneath it. The two tree shapes in A32 item 4 are the tests; assert the
   rows `CommentConversationBuilder` actually produces (ids, each once) and that the comment
   asked for is among them.
3. **The viewer is a session, not a name.** Hand the model the published auth context with its
   session generation (find what `auth/AO3AuthRepository.kt` publishes; other screens key on
   `generation` and `isSignedIn`). On a change: the kept chapter list and anything read for
   the old viewer are cleared and read again for the new one; nothing read for the old viewer
   is published after the change; the reader effect is keyed by the same context and does not
   override a chapter the reader has since chosen. Named sessions keep reading signed in; no
   failure is cured by an anonymous retry.
4. **Tests** (A32 item 8): a held draft lookup with a target change and with a viewer change;
   submit completion against a newer composer; both tree shapes; a same-name new session; a
   chapter index that completes after sign-in; and the two strengthenings A32 names for
   existing tests (root 77 against reply 88; both reads held by an explicit barrier instead
   of worker timing). Use a seam that lets a test hold a lookup; no `Thread.sleep`.

## What the result must say

What iOS does in each of the cases in 1 (with `path:line`), every place Android now differs
and why, every function you changed and the one-line reason, and anything in these files you
saw and left alone.
