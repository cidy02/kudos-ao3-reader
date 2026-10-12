# 3dd: the Manage pages below their first screen (Android)

Done 2026-10-12 by Claude, alone. Gate 2,632. Pictures: `shots/3dd/`. Follows 3dc.

## The same

- **Maintainers** (iOS opened by tapping its row; the direct debug row had only caught the
  page before it loaded, which was not a fault): Owners, Moderators, Invitations with
  "Invite as", Leave with "Step down as owner".
- **Moderation**, down the page: Recently decided, Membership requests with Accept and
  Decline, Maintainers, Reveal and anonymity.
- **Your sign-up**, down the page: the prompt, Offers with "Add an offer", the note.
- **Challenge**, down the page: Sign-up requirements, the tag sets, Assignments, At AO3.

## Fixed

- **Edit collection's Save was a line of text.** iOS ends the form with a filled "Save
  Changes". Android's is the same filled button the challenge pages got in 3dc.

## Different on purpose (already decided, left)

- Challenge's Assignments row has no "8 matched, 4 unmatched" on Android, and its note
  says only "AO3 matches participants." Android reads no assignment counts on that page
  and cannot ask for a pinch hitter in the app, so it does not say it can (the comment in
  `AO3ChallengeSettingsScreen` records it).

## Not checked

- "Withdraw sign-up": iOS shows it at the foot of Your sign-up; Android's code has it and
  the demo's page did not reach it in the two screens pictured.
- A sign-up's own page, a tag set's page, "Your items" on the AO3 Collections list, the
  Recently decided list; any write.
