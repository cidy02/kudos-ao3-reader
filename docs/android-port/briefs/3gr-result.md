# Brief 3gr / I7 result

A known collection kind asks for that challenge edit form only. A nil kind keeps today's gift-exchange request, then the prompt-meme form when that page is missing or does not parse. Any other gift failure still stops there. The kind is the one already parsed from the collection page. No new AO3 read learns it. Gradle and xcodebuild were not run.

## 1. Known kind asks for that form only

iOS `kudos-ao3-reader/Services/AO3Client+Challenges.swift:12` takes `kind: AO3ChallengeKind? = nil` and delegates to the static helper at `AO3Client+Challenges.swift:22`. A known kind fetches `challengeSettingsEditURL` (`AO3Client+Challenges.swift:44`) once and parses that page (`AO3Client+Challenges.swift:27`). Not-found and a page that does not parse throw. They do not open the other form. A nil kind copies the previous order at `AO3Client+Challenges.swift:31`: gift exchange, fall through only on `AO3Error.notFound` (`AO3Client+Challenges.swift:37`) or an unparseable gift page, then the prompt-meme form. `authenticatedRequest(for:)` in the views still builds a local request and does not choose the page that is fetched.

Android `account/AO3CollectionDetailRepository.kt:286` `readChallengeForm` does the same. `getChallengeSettingsForm` (`AO3CollectionDetailRepository.kt:123`), `getChallengeSettingsEdit` (`AO3CollectionDetailRepository.kt:133`), and `getChallengeSettings` (`AO3CollectionDetailRepository.kt:163`) pass the kind through. A known kind is one `fetch` of `ChallengeSettingsDestinations.challengeSettingsEditView`, then one session check. A null kind still reads the gift form, checks the session, and reads the prompt meme only when the gift result is `AO3Error.NotFound` or `AO3Error.Parse` (`AO3CollectionDetailRepository.kt:300`). The edit opening still continues to sign-ups, profile, and the collection edit form after that one settings form.

## 2. Callers that already have the collection page pass its kind

The collection page already stores the kind. iOS parses it in `Services/AO3Client+Collections.swift:375` and stores it at `AO3Client+Collections.swift:257`. Android parses it in `network/ao3/account/AO3CollectionParser.kt:19` and stores it at `AO3CollectionParser.kt:70`.

iOS `AO3CollectionDetailView.swift:366`, `:376`, `:386`, and `:408` pass `show.collection.challengeKind` into Sign-ups, Assignments, Prompts, and Challenge Settings. Each screen keeps `var challengeKind: AO3ChallengeKind? = nil` and sends that value on its settings read:

- `Features/Challenges/ChallengeSettingsView.swift:15`, read at `:542`. Children receive the same value at `:133` (edit), `:205` (prompts), `:421` (sign-ups), and `:607` (assignments). The display kind on the loaded form is not reused as the request kind.
- `Features/Challenges/ChallengeSettingsEditView.swift:31`, read at `:726`.
- `Features/Challenges/ChallengeSignUpsView.swift:13`, read at `:509`.
- `Features/Challenges/ChallengeAssignmentsView.swift:20`, read at `:510`.
- `Features/Challenges/PromptMemeView.swift:24`, read at `:555`.

Android collection detail calls `onOpenChallengeSettings`, `onOpenPrompts`, `onOpenSignUps`, and `onOpenAssignments` with `collectionShow.collection.challengeKind` at `account/AO3CollectionDetailScreen.kt:246`. `AppNavHost.kt:762` puts that kind on the settings, prompts, assignments, and sign-ups routes. `Routes.kt:178` adds an optional `&kind={kind}` query, omitted when the kind is null (`Routes.kt:207`), and `Routes.kt:208` reads it back. Each destination declares a nullable `kind` argument (`AppNavHost.kt:784`, `:834`, `:854`, `:893`) and passes `Routes.challengeKindFromRoute` into the screen (`AppNavHost.kt:788`, `:800`, `:806`, `:811`, `:814`, `:816`, `:845`, `:865`, `:904`).

The screens hand it to the state that performs the read:

- `AO3ChallengeSettingsScreen.kt:44` `challengeKind`, state at `AO3ChallengeSettingsState.kt:22`, read at `AO3ChallengeSettingsState.kt:52`.
- `AO3ChallengeSettingsEditScreen.kt:39`, state at `AO3ChallengeSettingsEditState.kt:23`, read at `AO3ChallengeSettingsEditState.kt:47`.
- `AO3ChallengeSignUpsScreen.kt:55`, state at `AO3ChallengeSignUpsState.kt:35`, read at `AO3ChallengeSignUpsState.kt:77`.
- `AO3ChallengeAssignmentsScreen.kt:47`, state at `AO3ChallengeAssignmentsState.kt:73`, read at `AO3ChallengeAssignmentsState.kt:113`.
- `AO3PromptMemeScreen.kt:49`, state at `AO3PromptMemeState.kt:39`, read at `AO3PromptMemeState.kt:109`.

`kind` is the last parameter and defaults to null, so a caller that does not have a collection page keeps the gift-then-meme probe. `AO3CollectionModerationScreenTest.kt:60` matches the new collection-detail callback shape. `CollectionManageRow` stays zero-arg.

## 3. Tests

No network. The Android tests use `ChallengeReadClient`, `ChallengeEditClient`, and `PromptMemeReadClient`. The iOS test calls the static fetch closure. They were not executed in this run.

`KudosTests/AO3ChallengeParsingTests.swift:324` `knownChallengeKindRequestsThatFormOnly`. A known prompt meme records only `promptMemeEdit` (`:341`). A known gift exchange records only `giftExchangeEdit` (`:344`). A known gift exchange that answers not-found (`:355`) or returns unparseable HTML (`:365`) throws and does not request the meme form. A nil kind still stops on a parsed gift page (`:369`), falls through to the meme form on not-found (`:375`) and on unparseable gift HTML (`:381`), and keeps a forbidden gift failure on the gift URL alone (`:391`). Reverted to an unconditional gift-then-meme probe, `:341` fails because the prompt-meme case requests the gift form first, and `:355` and `:365` fail because the refused and unparseable gift pages continue to the meme form.

`android/app/src/test/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsTest.kt:177` `knownKindRequestsThatFormOnlyAndUnknownKindStillProbes`. A known prompt meme is one GET of `memeUrl` (`:181`). A known gift exchange is one GET of `giftUrl` (`:186`). A known gift exchange that is not found stays on that URL and returns `AO3Error.NotFound` (`:192`). A known prompt meme whose HTML does not parse is one GET and `AO3Error.Parse` (`:198`). A null kind still does gift-then-meme on not-found (`:204`) and on unparseable gift HTML (`:209`), and stops after a parsed gift page (`:214`). `getChallengeSettings` and `AO3ChallengeSettingsState` with `PromptMeme` read `memeUrl` then the profile and do not count sign-ups (`:219`, `:224`). Reverted, `:181` fails because the meme case requests `giftUrl` first, `:192` fails because not-found falls through to a meme success, `:198` fails because the unparseable meme page is followed by the gift form, and `:224` fails because the state no longer receives the kind and the opening starts at `giftUrl`.

`android/app/src/test/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditTest.kt:46` `knownKindReadsThatEditFormAndUnknownKindStillProbes`. A known prompt meme's opening is the meme edit form, then sign-ups, profile, and collection edit, with no gift GET (`:50`). A known gift exchange uses the gift edit form and never requests `prompt_meme` (`:56`). A known gift exchange whose client answers not-found stops after that one GET (`:61`). A null kind on a meme collection still matches `openingReads`, gift then meme (`:66`). Reverted, `:50` fails because the meme opening inserts the gift GET, and `:61` fails because not-found falls through and the call returns the meme form.

`android/app/src/test/java/io/github/cidy02/kudos/account/AO3PromptMemeTest.kt:233` `knownPromptMemeAsksForThatScheduleFormOnly`. An owner state constructed with `PromptMeme` reads `promptSettingsUrl` then the first prompts page (`:238`) and does not read `promptGiftUrl` (`:239`). Reverted, `:238` fails because the state drops the kind and the owner opening starts with `promptGiftUrl`.

`android/app/src/test/java/io/github/cidy02/kudos/app/RoutesNavigationTest.kt:175` `knownChallengeKindRoundTripsOnEverySettingsRoute`. Settings, assignments, sign-ups, and prompt meme each navigate with `PromptMeme` and read `prompt_meme` back (`:186`). A settings route built without a kind reads null (`:190`). The test graph declares the nullable `kind` argument at `RoutesNavigationTest.kt:54`, `:62`, `:69`, and `:75`. Reverted, `:186` fails because the built route no longer carries `prompt_meme`.
