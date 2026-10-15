# A57: iOS's session, cookie, archive and import rules: does Android's code keep them?

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A57-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

The method of your A52 to A56. Android: `~/kudos-android-lane` at `b3db90eb` (read-only). iOS:
`/Users/cidy02/kudos-ios-polish/` (read-only; `kudos-ao3-reader/`, `KudosTests/`). Binding:
`docs/AO3_NETWORKING_POLICY.md`, `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

Read every `@Test` in these iOS files: `AO3AuthTests`, `AO3SessionVaultM13Tests`,
`AO3SessionVaultM14Tests`, `AO3SessionVaultM16Tests`, `AO3StoredCookieM10Tests`,
`CookieAllowListTests`, `AO3RedirectCookieRelayTests`, `LiveAO3SessionValidatorRelayTests`,
`AO3ClientPolicyTests`, `AO3ClientTests`, `AO3RequestCoordinatorTests`, `RequestCoalescerTests`,
`ReaderWebIsolationTests`, `ArchiveTrustBoundaryTests`, `MiniZipCRCTests`, `MiniZipHostileTests`,
`MiniZipZip64Tests`, `HostileZipFixture`, `StaleArchiveKeepsNewerEPUBTests`,
`ReplaceIsTheSnapshotTests`, `ReplaceUndoCopyRecoveryTests`, `PendingAssetIsNotAbsenceTests`,
`ArchiveDeletionScheduleTests`, `CrossPlatformFolderSyncTests`, `LocalDataClearingTests`,
`UserDocumentImportTests`, `ImportedDocumentConverterTests`, `PDFWorkConverterTests`,
`EPUBBuilderTests`, `EPUBDigestHonestyTests`, `WorkDownloadTests`, `WorkUpdateCheckerTests`,
`WorkAvailabilityTests`, `WorkAvailabilitySweepTests`, `PersistenceGateSuites`,
`ConversionSidecarIsFetchedTests`, `DownloadDateDetectorTests`.

For each test: quote its assertion (`file:line`), say in one line what it guarantees, then
**kept** (quote the Kotlin, `path:line`; name Android's own test of it if any), **missing**
(quote the code that breaks it; say what goes wrong for a reader), **not applicable** (say
which feature Android lacks or does differently by platform design, e.g. Keychain vs Android
Keystore), or **unsure**. Without quotes on both sides it is **unsure**.

Weigh most: a session or cookie that leaks to a non-AO3 host, outlives sign-out, or survives a
failed delete; a request sent outside the pacing; a hostile archive (zip slip, zip bomb, a
huge entry, a CRC lie) accepted; a restore or sync that loses a newer EPUB or a reader's data;
an import that writes outside the app's folders; the reader's web view reaching the network.

## Report

A table per test file, then **the missing ones worth fixing first**, one line each, the most
harmful first. Stop where you run out of time and say where. Say plainly where Android is right.
