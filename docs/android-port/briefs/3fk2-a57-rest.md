# Brief 3fk-2: the rest of A57 (items 4 to 8)

Same rules as brief 3fk (`docs/android-port/briefs/3fk-a57-client-cookie-archive-fixes.md`).
Work on a fresh branch at the dispatch commit, which already holds your 3fk (items 1, 2 and
3's identity allow-list, landed by Claude). End with `docs/android-port/briefs/3fk2-result.md`.

**SameSite (your stop in 3fk): decided, not to be built.** Android's stored cookie keeps no
SameSite, and the stored session format stays as it is. Chromium's WebView treats a cookie
without SameSite as Lax, which is the value iOS stores, so nothing a reader sees changes.
Claude records this in `DECISIONS.md`.

Do items 4 to 8 of brief 3fk, in order, each confirmed against the code first, each with a test
porting the iOS assertion:

4. Sign-out leaves path- or subdomain-scoped AO3 cookies in the WebView
   (`logoutClearsPersistedAndWebSessions`).
5. Hostile EPUBs (`MiniZipHostileTests`): the EPUB preflight rejects unsafe and duplicate entry
   names, a declared-oversize entry, an implausible compression ratio, and an aggregate
   expanded-size budget, at iOS's numbers.
6. Blank usernames build `/users//…` (`buildsMarkedForLaterURL`, `buildsHistoryURL`,
   `buildsBookmarksURL`): return null as iOS.
7. Availability (`WorkAvailabilityTests`, `WorkAvailabilitySweepTests`).
8. Gift recipients and the work page's published/updated/status fields, if Android shows them.
