# A39: every write whose screen then reads a page the page cache can answer

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A39-result.md`. No helper scripts left behind.

Android only: `android/app/src/main/java/io/github/cidy02/kudos/`.

Background. `network/ao3/AO3PageCache.kt` keeps pages for 5 minutes and answers reads from
memory. A screen that writes to AO3 and then reads its page again must either pass
`bypassCache = true` or remove the page from the cache first; otherwise it shows the page from
before the write. One such fault was found on the emulator and fixed (`author/AuthorProfileScreen.kt`,
`onSaved = { ...loadHeader(bypassCache = true)... }` after a bulk edit). This job finds the
others. Claude will check every row, so what helps is an **index of where to look**: every row
must quote the Kotlin with `path:line`. A row without a quote is worth nothing: leave it out.
Never write "none" without naming the files you searched and the words you searched for.

Do this, in order, and stop where you run out of time (say where):

1. **Reads through the cache.** Every call that reads through `AO3PageCache` (search for
   `pageCache`, `AO3PageCache`, `bypassCache`, `cachedPage`, `staleIfError` and whatever
   `AO3PageCache.kt` names its read function): the repository function, `path:line`, which
   address it reads, and its `bypassCache` parameter if it has one.
2. **Removals.** Every call that removes or clears entries of the cache (`remove`,
   `invalidate`, `clear`, `forget`): `path:line`, and what triggers it.
3. **Writes beside those reads.** For each screen or view model that calls one of the reads in
   step 1: every AO3 write that screen can start (search its file for `writes.`,
   `AO3WriteRepository`, `submit`, `post`, `delete`, `subscribe`, `unsubscribe`, `mark`), and
   **the exact lines that run after the write succeeds**. For each write say which of these is
   true, with the quote: (a) it re-reads with `bypassCache = true`; (b) it removes the page
   from the cache first; (c) it re-reads without either; (d) it does not re-read, and changes
   the screen's state by hand; (e) it does not re-read and changes nothing.
4. **Screens that do not write but show a page another screen changes.** For each write found
   in step 3: which other screens read the same address through the cache (from step 1)? For
   example a work edited in the work form, then the author's works list; a series edited in
   the series form, then the series page; an Inbox item marked read, then the Inbox opened
   again from Account.

End with a table: number, the write (`path:line`), the read that follows or the other screen
that shows the same page (`path:line`), which of (a) to (e), one line.
