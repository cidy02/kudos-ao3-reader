# A50: the second reviews owed since 2026-10-10 (Android)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A50-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

Read the Android code as it stands on `android/redesign-parity` at `10883501` (in
`~/kudos-android-lane`, read-only; your own worktree is behind it). iOS, where a change copies
it, is `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). The networking rules
are binding: `docs/AO3_NETWORKING_POLICY.md` (authenticated reads only of the reader's own lists
or a page they opened; no background or bulk reading; a write only when the reader asks, sent
once, never retried; pacing never weakened).

Each change below landed with one reader. Find what is **wrong**: a write sent twice or
without the reader asking, a read the policy forbids, data a reader loses, a wrong screen state.
Every finding quotes the Kotlin with `path:line`, says what happens to a reader, and how sure
you are; without a quote, leave it out. Say plainly when a change looked right.

In this order; stop where you run out of time (say where):

1. **3ci, Subscribe and Unsubscribe on an author's page** (`a5c14a94`; `briefs/3ci-result.md`).
   One POST per tap? A second tap while the first is on its way? The state shown after a
   failure? Against iOS's confirmation.
2. **3co step 7, Clear History** (`c2442cd6`). The same questions, and: does anything clear
   the local history before AO3 says yes?
3. **Favourite authors' "With new work"** (`78beddc1`, `1b25f24d`) **and the accounts read
   from bylines** (`2ddab9c7`, brief items 3, 3a, 3b in the Living Prompt's §10). How many
   AO3 reads does one look at the Authors row cause, and when? Is any of it background or
   bulk reading by the policy's words? Can an account read from a byline's words be the
   wrong person (a pseud that is somebody else's account name)?
4. **3ch, the writer's own totals** (`824dd439`): one read of `/users/<name>/stats`, own
   account only. Is the guard really in the repository, so no screen can ask for another's?
5. **3df, comments open on the newest** (`1c6bd366`). Can a reader land on an empty or wrong
   page (a work with one page of comments, a chapter's comments, a new comment just posted)?
6. **3cf, the challenge settings edit form** (`briefs/3cf-result.md`; and `7ea341fd`, the form
   refusing a change to a radio button). Does Save send exactly what changed, once?
7. **3cg, the comments model's one captured context** (`briefs/3cg-result.md`). Can a reply
   or an edit go to the wrong comment or work after the screen's work changes?

End with a short list: the findings worth fixing first, one line each.
