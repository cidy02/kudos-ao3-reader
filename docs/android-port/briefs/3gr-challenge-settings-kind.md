# Brief 3gr / I7 (both apps): ask for the challenge form the collection's kind names

**Write code in these two worktrees only: Android `/Users/cidy02/kudos-agent-grok` (branch
`android/agent-grok-3gr`) and iOS `/Users/cidy02/kudos-agent-ios2` (branch `claude/agent-ios2-i7`).
Do not commit, push, switch branches, sign in, run Gradle or xcodebuild, or contact
archiveofourown.org.** Claude builds, tests and lands both. Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gr-result.md` in the Android worktree FIRST and write each item into it as
you finish it, with `path:line` on both apps and, for each test, what it would do if the fix were
reverted (it must fail).

Owner decision (2026-10-07): **reads AO3 will refuse are not made.** Both apps read a collection's
challenge settings by asking for the gift-exchange edit form first and falling back to the prompt
meme form when AO3 answers "not found": iOS `Services/AO3Client+Challenges.swift:9`
(`challengeSettings(slug:request:)`), Android `account/AO3CollectionDetailRepository.kt:129`. For a
prompt meme that first request is always refused. Both apps already parse the collection's own
kind from its page (iOS `AO3Collection.challengeKind`, `Services/AO3Client+Collections.swift:257`;
Android `AO3Collection.challengeKind`, `network/ao3/account/AO3CollectionParser.kt:19`).

1. When the caller knows the collection's kind, ask for that form only. Fall back to today's order
   only when the kind is unknown (a nil kind), and keep the fallback's existing behaviour exactly.
2. Pass the known kind from every caller that has the collection page in hand (iOS:
   `ChallengeSettingsView`, `ChallengeSettingsEditView`, `ChallengeSignUpsView`,
   `ChallengeAssignmentsView` and whatever opens them; Android: the collection detail repository and
   the screens it serves). Do not add a new AO3 read to learn the kind.
3. Tests on both apps (no network: the existing fake clients): a known prompt meme makes one request,
   to the prompt meme form; a known gift exchange one request, to the gift form; an unknown kind keeps
   the gift-then-meme order and its "not found" fallback.

Nothing else changes. Builds for iOS and macOS must stay clean (iOS file is shared with macOS).
