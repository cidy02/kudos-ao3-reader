# D9 result: owner-summary facts

Fact refresh only. Sources read through the Living Prompt's 2026-10-24 08:00 entry;
the matrix still says 25 ✅ and 2 🟦. A100's gate and re-shoot are not reported as done.
This note was written before editing `OWNER-SUMMARY.md`.

Sources below:
- **LP** = `~/kudos-android-lane/docs/android-port/LIVING-PROMPT.md`.
- **Android log** = `git -C ~/kudos-android-lane log --since='2026-10-23 12:00'`, including commit bodies.
- **iOS log** = the same read-only log in `~/kudos-ios-polish`.
- **Decisions** = this worktree's `docs/android-port/DECISIONS.md`.

## Facts changed (old → new)

1. Draft dated 2026-10-23 12:30 → fact refresh dated 2026-10-24, through LP's 08:00 entry. The supplied brief calls the original the 12:24 draft; its actual header says 12:30. Source: original header; LP §12, 10-24 08:00.
2. 13 of 27 parity rows verified, 14 waiting → 25 ✅, 2 🟦, 0 🟨. The two are Library (filter tint) and Author pages (Load More ink), waiting on A100's gate and re-shoot. Source: LP §7's 23:15 “Where it stands”; §12, 10-24 08:00.
3. 3hb, 3hc, pairing and Group variants in flight → landed: `6c002b44` (3hb plus pairing/fandom list), `76c7e273` (A88d's help-sheet and bulk-Add fixes), `5455f869` (3hc finished as 3hc2, plus 3hd), `5c6b0f1c` (queue-test teardown race). Source: Android log; LP §12, 18:27.
4. A88c's Android faults described as current → described as findings since fixed and checked in A97. Source: LP §12, 21:20; Android log `c314551f`.
5. Find/Note's keyboard focus listed as a fix to make → kept, as on iOS; the iPhone shots lacked a keyboard because of the Simulator's hardware-keyboard setting. Source: Android log `6c002b44`; LP §10, 14:41 lessons.
6. Sticky-field seam fix alone → final fields scroll away under one wash; reader cards stay glass in Light and opaque in the other themes; Customize Theme stays opaque. Source: Android log `5455f869` (3hd).
7. 3ha's nine screens, the parent URL, OLED Revoke and Sepia formatting tray still to shoot → A88d's fixes landed; A97 and round 2 checked the follow-up pairs; the URL was re-shot after T-443. Revoke's dialog is accepted in D7; formatting tray matches per §7. Source: LP §7 Settings/Comments/Writing rows; §10 19:25; §12 21:20 and 23:15; Decisions D7.
8. A88c treated as the last look → add A97 (38 re-shot pairs; all earlier fixes hold; 2 differs, 8 minor, 2 capture problems). Gemini's planned second read failed on network/quota, so do not call it a two-reviewer pass. Source: LP §12, 21:20; Android log `c314551f`.
9. No A96 landing → add `82626348`: series figure/fandom icons, creator link ink, “by” on detailed work cards, mixed-case Bookmarks heading. Source: Android log; LP §10 19:57 and §12 21:20.
10. No A98 landing → add `c314551f`: current-speed pill and Sample Text ink, primary-ink page-jump ends, filter menus/palettes, challenge title-or-slug palette, short recovery time, New Work first, chapter glyph, help title. Keep My Works totals. Source: Android log.
11. Thread only previously seen on emulator → A99 `e347c8d2` added a debug route; round 2 paired it for the first time and it matches. Source: Android log; LP §12, 23:15.
12. No round 2 outcome → A98's fixes hold, Thread matches; filter tint and Load More ink remain the two-row follow-up. Source: LP §7; §12, 23:15.
13. No D7/D8 decisions → accepted Material controls, Android chrome and differing demo data recorded as D7 `edf3d2fd` and D8 `a39d9b29`. Examples include revoking in a dialog, outlined fields, page-jump text buttons, chapter glyph and short recovery date. Source: Decisions' two final entries; Android log.
14. No A100 state → applied and reviewed in the lane, gate-31 running; the re-shoot of Library filters and Author bookmarks still follows. Include the requested pending marker once in the paragraph about the two rows. Source: LP §12, 10-24 08:00 and 10-23 23:15. No outcome invented.
15. “3,397 green, 1 skipped” at `f8d65081` as latest gate → gate-30 at `c314551f`: 3,455 tests, four full-run failures; two stale-theme tests fixed (10/10 affected class), two load-only failures pass alone (15/15 and 8/8). Assemble and release compile pass; lint 0 new, 4 gone. Do not call all 3,455 green or carry the old skipped count forward. Source: Android log `c314551f`; LP §12, 22:15.
16. Build/tests item unconditionally “done at last landing” → report gate-30's rerun qualifications and gate-31 running. Add A99's separate 79/79 comments tests. Source: Android log `c314551f`, `e347c8d2`; LP §12, 10-24 08:00.
17. All 22 failures in 3ha's first run attributed to demo-network leakage → sixteen later tests were affected by that leakage; six asserted pre-A92 behaviour. Source: Android log `f8d65081`.
18. I12 pronunciation protection and iPhone code-comparison fixes “landing” → landed as T-437. Source: draft's T-437 list; LP §12, 10-23 10:00.
19. I15 “landing as T-440,” URL said fixed → T-440 `9dc1e095` landed but did not solve AX5 hyphenation; T-443 `f24572c2` wraps at any character and was re-shot in all five columns. Source: iOS log; LP §10 19:25 and §12 19:25.
20. I16 “landing as T-441” → T-441 `e654c69e` landed: wrapping Sample Text, readable current-speed pill, working AX5 pronunciation routes; follow-up columns usable. Source: iOS log; LP §10 19:25.
21. No T-442 → add `24e04efb`: Comments uses the shared offline-error list for kept pages and cold failures. Source: iOS log; LP §10, landed since 14:41.
22. No T-444 → add `7f479443` (I18): paste with a line break keeps editing and undo, VoiceOver gets the placeholder, Dynamic Type reapplies attributes. Source: iOS log; LP §12, 21:20.
23. No T-445 → add `d3e66077` (I19): AX5 editor preserves writing room with one recovery line, scrolling formatting chips and Editor help holding both notices. Source: iOS log; LP §12, 23:15.
24. iOS changes stop at T-439 → through T-445. State the testing limits: T-440–T-442 ran full suites with the known 10 failures; T-443–T-445 ran affected suites, not full suites. Source: iOS log.
25. Every A88c finding “real” and all audits complete → remove that absolute claim: keyboard-focus item withdrawn; A93's five P3s fixed in 3hd; A94 led to 3hc2; A95's P1 rejected on simulator, four minor URL-field points fixed in T-444. Keep bug-hunt status distinct from the open A100 parity follow-up. Source: Android log `6c002b44`, `5455f869`; LP §10 A95 settlement; iOS log `7f479443`.
26. “Every screen … fixed to match” → qualify to the 25 closed rows and accepted platform differences; retain the two A100 rows as open. Source: LP §7; Decisions D7/D8.
27. No team handover → Claude-CLI orchestrates until Claude-Code returns at 2026-10-24 22:00, then hands back. Source: LP §0, owner 18:22; §8.
28. No current team availability → Gemini out on both accounts, Grok out of balance; Sonnet also out on both from 10-24 07:40, so D9 moved to Codex. Source: LP §8; §12, 10-24 08:00.
29. No Duo preparation → Duo2 research done and checked, `67f02ddf`; Duo1 runs the cover screen but needs the owner's Device Hub pose click. Parity comes first; Duo waits. Source: LP §0 owner 18:33 and 22:20; §10 Duo1/Duo2; Android log.
30. Only the numbered Android questions → also list the two unnumbered asks: Device Hub's pose click and permission to delete five idle simulators, about 27 GB. No deletion approved or performed. Source: LP §10 Duo2 and disk paragraphs; §0 owner 22:20.
31. Q3's current default “no, app accent” → screen wash, per the later owner instruction and T-399/Android `c268ba1a`. Preserve the numbered registry's 34/7/1/26 bookkeeping for Claude-CLI's final pass rather than silently adjudicating its stale open designation. Source: LP §10 wash-tint directive; Decisions 2026-10-12 “The tab bar and chrome buttons take the colour of the screen on top”.
32. Android branch at `f8d65081` with fixes in flight → pushed through `a39d9b29`; last app commit `e347c8d2`, A100 applied but not yet landed. Source: Android log; LP §12, 10-24 08:00.
33. iOS polish `bd533264` with I15 uncommitted/I16 next → pushed `d3e66077` (T-445); integrate `bbe07bdc` through T-439 → pushed `211d2076` through T-445. Source: iOS log; LP §12, 23:15.
34. Audit index ends at A92/A88c → mention A93–A99 and round 2, with A100's pending work in `briefs/`; don't claim every result is an `audits/` file with triage. Source: LP §10/§12; Android log `a39d9b29`.
35. Each A82 half said to have two code reviewers → first half Codex, second half Claude-CLI (A84a/A84b), as the draft's later A84 paragraph already says. Source: LP §7 “Audits by pair”.
36. 3go attributed to `8c80b3b7` → retain 3go without that hash: LP assigns `8c80b3b7` to 3gp, not 3go. Retain LP's 62 present/10 gaps account; Decisions separately says 62 of 82 checks, so do not substitute that conflicting total. Source: LP §5d W2/A78 row and §10 10-22 05:20; Decisions' A77/A78 entries.
37. No-mockup counts 54/21/28/5 and 45 restyled → omit the unsupported counts; retain the required inventory and its per-screen account. The five “can't be compared yet” claim also conflicts with LP §7's current four excluded screens. Source: LP §0's no-mockup documentation requirement and §7 “Screens no pass can compare yet”. The permitted sources do not establish current no-artboard totals.
38. Artboard comparison labelled “Not done” → label it “Pass scope”: the passes compare phones, while iOS's own loop checks artboards. Source: LP §7's rule.

The numbered owner-question bookkeeping is preserved as the draft reports it; the two new
operational asks are separate, not invented questions 35/36. Existing real-device checks,
unmerged-main status and installed-iPhone revision are retained. No build, simulator,
network, branch switch, commit, push or `TASKS.md` edit was performed.
