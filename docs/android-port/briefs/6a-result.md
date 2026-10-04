# 6a result: four Settings screens in the old design

Done by Claude, one screen at a time (no agent is available until 2026-10-06).

## About (`account/AboutScreen.kt`) — done

Redrawn as iOS's `AboutView`, with the parts the other Settings pages use (`SettingsPage`,
`SettingsPanel`, `SettingsSection`, `SettingsActionRow`).

| | Before | After |
|---|---|---|
| Header | the shell's title bar, then "Kudos" | kicker "SETTINGS", title "About"; then a panel with the book icon, "Kudos" |
| Version | "Version 0.2.1 (9)" | "Version 0.2.1 (9) · b43fd9e": the commit too, on a build that knows it, as iOS and as the bug report already had |
| Tagline | "A native Archive of Our Own reader for Android." | "Read and save Archive of Our Own works on your Android devices." (iOS's, with "Android" for "Apple") |
| License | "Kudos is free software, released under the GNU Affero General Public License v3.0 (AGPL-3.0). You may use, study, share, and modify it under the terms of that license." | "Kudos is free to use, study, share, and change under the **GNU Affero General Public License v3.0 (AGPL-3.0)**." |
| Components | Jsoup ("HTML parsing for AO3 scraping."), Readium Kotlin Toolkit ("The EPUB reading engine.") | Jsoup ("Reads AO3 pages so Kudos can show works."), Readium Kotlin Toolkit ("Displays downloaded works in the reader."), ao3_api ("Helped guide how Kudos reads AO3 pages.", "Reference") |
| Help & Feedback | a "Report a Bug" outlined button near the top; "Source: github.com/cidy02/kudos-ao3-reader" as a link at the bottom | section "Help & Feedback": "Report a Bug", "View on GitHub" |
| Disclaimer | two paragraphs | iOS's one: "Kudos is an unofficial personal project. It isn't affiliated with or endorsed by the Organization for Transformative Works or Archive of Our Own. AO3 doesn't provide an official way for apps to read its pages, so Kudos reads the same public pages you can visit." |

Callbacks: `onReportBug` unchanged. The component links and the repository link open the same
URLs as before. The unused `modifier` parameter is gone.

**Android had, iOS lacks, removed:** "AO3 login uses AO3's real login page. Kudos never stores
your password. Session cookies stay on this device and are excluded from backups." The Backup
screen says the same about passwords and cookies.

**Not audited:** Android bundles more libraries than the three listed. iOS lists three and has a
separate, unlinked notices screen (`LegalNoticesView`).

## Report a Bug (`account/BugReportScreen.kt`) — done

Redrawn as iOS's `BugReportView`. What it collects and what it opens are unchanged: the same
issue body, the same two GitHub URLs.

| | Before | After |
|---|---|---|
| Intro | the same sentence, under a "Report a Bug" headline | the same sentence, in a panel under the page title |
| Field | Material outlined field, label "What went wrong?" | section "What went wrong?", a panel field, the same placeholder |
| Details | "Included with your report", "App version", "System" | the same, as form rows; the values wrap so they are seen whole |
| Details note | "Only these app and system details are attached — no personal data, and never your AO3 account." | "Only these app and system details are sent with your report. Nothing personal is included, and never your AO3 account." |
| Actions | "Continue on GitHub" (filled), "Browse existing issues" (outlined), "Cancel" | "Continue on GitHub", "Browse existing issues" as action rows |
| Footnote | "Please don't contact the AO3 team about Kudos — they can't provide support for this app." | "The AO3 team can't help with Kudos, so please don't contact them about it." |

Callbacks: `onBack` became `onCancel`, optional. Opened from About the page is pushed and the
shell's back button leaves it, so there is no Cancel row. Opened by a shake it stands alone over
the app, and "Cancel" is there as before. The text now survives a rotation
(`rememberSaveable`).

**iOS has, Android lacks, left out:** the screenshot section. iOS offers the screenshot it took
at the shake; Android takes none.

**Not seen on the emulator:** the shake path. The emulator's sensors could not be made to
trigger it.

## Check Availability (`settings/AvailabilitySweepScreen.kt`) — done

This one is more than a redraw, because the two apps did it differently:

| | iOS | Android before | Now |
|---|---|---|---|
| Settings › Preservation › "Check Availability…" | opens the screen | **started the check at once**, with a line of status under the row | opens the screen |
| The screen | states the cost first ("Before you start"), then "Check Now"; progress; a result; the list of works no longer on AO3 | only that list, under a Material title bar | iOS's screen |
| "Unavailable Works" row on Preservation | none: the list is on the screen | a second row opening the list | removed; the list is on the screen |

iOS's reason is in its code: a check is one AO3 request for each work, and the reader is the
only one who can decide that is worth it, so the screen says so before any request is sent.

Strings, all iOS's: "Before you start"; "Kudos will check N work(s), one at a time."; "AO3 can't
tell Kudos what changed, so each work must be checked separately. Kudos waits about two seconds
between works to avoid overloading AO3; you can stop anytime and keep the results so far.";
"N imported work(s) came from other sites, so Kudos can't check them on AO3."; "This check covers
up to 150 works. Start it again later for the rest; works checked during the past week are
skipped."; "Checked X of Y"; "Finished" / "Stopped"; "N work is / works are no longer on AO3";
"Kudos marked them as no longer on AO3. Any downloaded copies are now treated as the last copies
you have and will be kept permanently."; "Everything checked is still on AO3"; "Checked N.",
"Skipped N checked in the last week.", "N still to check. Run this again to continue."; "No
longer on AO3 (N)"; "Check Now" / "Checking…"; "You checked every AO3 work in your Library within
the past week."

Gone: "Sweeping…", "Sweep complete: X checked, Y unavailable.", "Sweep failed: …", "Unavailable
Works", "No works are currently marked unavailable on AO3." (iOS shows no list when there is
none). Kept because a test pins it: the row's accessibility label "Check library for
deleted/hidden works on AO3."

Callbacks: `onOpenWork` unchanged. `onBack` is gone (the shell's back button). The screen now
takes the `WorkAvailabilitySweep`, and `SettingsScreen` and the Preservation page no longer do.
`WorkAvailabilitySweep` gained `counts()` and a progress callback, and a check stopped in the
middle of a request now returns its summary instead of throwing.

**Different from iOS, by placement:** iOS has "Stop" and "Done" in the sheet's toolbar. Here the
page is pushed: "Stop" is a row under "Checking…", and the back button is Done. Leaving the
screen stops the check on both.

**Different from iOS, found and not changed** (rules of the check, not of the screen):
- Android checks saved library works; iOS checks every work that is not in Recently Deleted.
- Android never checks a work again once it is marked "no longer on AO3"; iOS checks it again
  after a week, so a work that comes back loses the mark.
- iOS counts a work as checked even when the answer was inconclusive; Android counts only the
  conclusive ones.

**Not seen on the emulator:** the running state and "Stopped". The demo has one work to check,
so the check ends at once.

## Found on the way, fixed

`SubjectFormRow` gave the label what was left after the value. A long value took the row and
the label was one letter wide, a letter to a line ("System" on Report a Bug). The label now
keeps its width and the value takes the rest. On the Settings hub the values moved by two
pixels; nothing else changed.

`SettingsPanel` shrank to the width of what it held. A panel with one short line was narrower
than its neighbours ("Finished" on Check Availability). A panel now spans the page.

## Seen on the emulator

About and Report a Bug in Light, OLED and Sepia and at the largest text size; About scrolled to
its end; "Report a Bug" from About opens the report; typing into the field works.

Check Availability in the same three themes and at the largest text size; reached from
Settings › Preservation; one check run in the demo ("Finished", "Everything checked is still on
AO3", "Checked 1."), with the demo database copied first and put back after, because a check
rewrites a work's AO3 details from the demo's one fixture.

## Still to do

Queue Storage.
