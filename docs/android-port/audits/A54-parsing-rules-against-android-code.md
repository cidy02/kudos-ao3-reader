# A54: iOS's AO3 page-parsing rules that Android has no test for: does Android's code keep them?

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A54-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

The same method as your A52 (`docs/android-port/audits/A52-result.md`), for the sections A52
skipped. Read Android at `~/kudos-android-lane` `323ee898` (read-only) and iOS at
`/Users/cidy02/kudos-ios-polish/` (read-only; app in `kudos-ao3-reader/`, tests in
`KudosTests/`). Android's fixtures: `android/app/src/test/resources/ao3/` and
`android/app/src/debug/assets/fixtures/`; iOS's: `KudosTests/Fixtures/`.

`docs/android-port/audits/A25-result.md` (a Gemini index; leads only, often wrong in detail)
marks rules `[uncovered: …]`. For these sections: `AO3CommentsParseTests`,
`AO3InboxParseTests`, `AO3NamedSubscriptionsParseTests`, `AO3PreferencesParseTests`,
`AO3ReadingsParsingTests`, `AO3SubscriptionsParseTests`, `AO3UserStatsParsingTests`,
`AO3CollectionParsingTests`, `AO3ChallengeParsingTests`, and any other AO3 parsing section in
A25 (skip Kokoro). For each `uncovered` rule:

1. Read the iOS test (quote the assertion with `file:line`) and say in one line what it
   guarantees a reader (what they would see wrongly if the rule failed).
2. Decide for Android: **kept** (quote the Kotlin with `path:line`), **missing** (quote the
   code that breaks it; say what a reader sees), **not applicable** (no such feature: say
   which), or **unsure** (say what you could not find). Where both apps parse the same fixture
   file, say whether Android's parser, fed that fixture, would satisfy the iOS assertion.
3. A25 may name a rule that does not exist or misdescribe it; say so and move on.

Without a quote on both sides, a row is a lead, not a finding: mark it **unsure**. Pay special
attention to anything that turns an unrecognised or changed AO3 page into an empty, wrong or
silently partial screen (the comments page did this until 3el), to identities (pseud vs
account), and to counts and pagination.

## Report

A table per section (rule, iOS quote, verdict, Android quote, what a reader sees), then **the
missing ones worth fixing first**, one line each, the most misleading first. Stop where you run
out of time and say where. Say plainly where Android's code is right.
