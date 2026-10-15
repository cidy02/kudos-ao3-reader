# Brief 3fk: A57's client, cookie, archive and parsing faults

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fk`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. **No Room schema or
backup-format change** (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits afterwards, so make what you write compile (`SavedWork` needs
an `author`, for one). End with `docs/android-port/briefs/3fk-result.md`. Binding:
`docs/AO3_NETWORKING_POLICY.md`, `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

Your A57 (`docs/android-port/audits/A57-result.md`) stopped at your usage limit before its
priority list; Claude ranked its 70 missing rows. Claude fixed two in 3fj (a permanent delete
removes an imported original; a restore cannot switch off the delete confirmation); leave
those. For each below: confirm it against the code at the dispatch commit, fix it as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only), with a test porting the iOS assertion. Most
important first; stop where you run out of time and say where.

1. **The client sends to any host it is given** (`AO3ClientPolicyTests.lookalikeAndForeignHostsAreRejectedWithoutNetwork`,
   `imageDataAndGetHTMLRefuseForeignHosts`). The session cookie is already AO3-only
   (`AO3CookieJar`), but `OkHttpAO3Client.get`, `getBytes` and the POST path will request a
   lookalike, foreign, cleartext or loopback address. Refuse anything but HTTPS AO3 hosts before
   any network, as iOS. Tests across the suite point the client at local MockWebServer or
   interceptor hosts: make the check injectable (default: AO3 only) and pass an allow-all only
   in those tests; say which tests changed.
2. **Blurbs that fail to parse look like an empty result** (`blurbsPresentButNoneParseableThrowsInsteadOfLookingEmpty`,
   `accountBookmarksPageStillThrowsWhenAWorkHeadingFailsToParse`): fail closed as iOS (and as
   comments now do, 3el), so markup drift shows an error with Retry, not "no works".
3. **Non-identity cookies kept** (`CookieAllowListTests`, `captureAO3CookiesFiltersNonIdentity`,
   `onlyAllowListedCookiesArePersisted`): persist, reinstall and merge only iOS's identity
   cookie names. Keep SameSite where the session already stores attributes, if it does;
   otherwise say what a stored field would need and stop (no format change).
4. **Sign-out leaves path- or subdomain-scoped AO3 cookies in the WebView** (`logoutClearsPersistedAndWebSessions`).
5. **Hostile EPUBs** (`MiniZipHostileTests`): reject unsafe entry names, duplicate names,
   declared-oversize and implausible-ratio entries, and an aggregate expanded-size budget in the
   EPUB preflight, as iOS's numbers. Android does not extract EPUBs to disk, so this guards the
   reader against a zip bomb rather than a write outside the folder; say so.
6. **Blank usernames** build `/users//…` (`buildsMarkedForLaterURL`, `buildsHistoryURL`,
   `buildsBookmarksURL`): return null as iOS.
7. **Availability**: a one-work refresh's 404 marks the last copy; a recovered work ID is kept;
   an inconclusive sweep check is counted as checked (`WorkAvailabilityTests`, `WorkAvailabilitySweepTests`).
8. **Gift recipients and the work page's published/updated/status fields** (`parsesGiftRecipientsFromTheBlurbHeading`,
   `parsesWorkPageMetadata`, `parsesWorkInProgressStatusFromUnclassedLabel`), if Android shows them.

Leave the document converter's gaps (chapters, metadata and word counts for imported HTML,
text and PDF; A57's `UserDocumentImportTests`, `ImportedDocumentConverterTests`,
`PDFWorkConverterTests`, `EPUBBuilderTests`): they are a feature to build, not a fault.
