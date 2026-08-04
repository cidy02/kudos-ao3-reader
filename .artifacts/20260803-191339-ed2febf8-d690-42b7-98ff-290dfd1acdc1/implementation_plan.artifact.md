# Phase 3: Account / Auth / Author profiles

This phase focuses on bringing full parity to the Account and Author profile areas, including native author dashboards, native login, account preferences, and posting-pseud management.

## User Review Required

- **Native Login Security**: The native login form uses a hidden WebView to submit the form via JS. This is security-sensitive and should be reviewed to ensure credentials are handled safely (Item 7).
- **Session Encryption**: We are migrating from plaintext JSON to `EncryptedFile` using Android Keystore. Existing sessions will be migrated on first load (Item 6).

## Proposed Changes

### Author Profiles (Items 1-4)
Already partially implemented in untracked files. I will verify and finalize these.

#### [AuthorProfileScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt)
- Verify 4-tab layout (Works, Series, Bookmarks, About) matches iOS.
- Ensure pseud scope switching is fully wired.
- Add moderation actions (Block/Mute) if not already fully functional.

#### [AO3AuthorParser.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorParser.kt)
- Verify parsing of Dashboard, About, Series, and Bookmarks pages.

---

### Posting-pseud Selection (Item 5)

#### [AO3WriteFormParser.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteFormParser.kt)
- Add `parsePostingPseuds` to extract all available pseud options from a form.

#### [AO3WriteRepository.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt)
- Integrate `AO3PostingPseudStore` to read/persist preference.
- Update `createBookmark` to use the preferred pseud if available.

#### [WorkDetailScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt)
- Add pseud selection dropdown to the Bookmark dialog.

---

### Native Login (Item 7)

#### [AO3NativeLoginScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt)
- Verify the JS-injection based native login works as expected.

#### [AppNavHost.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt)
- Switch `Routes.AccountLogin` to use `AO3NativeLoginScreen` by default.

---

### Account Overview Enhancements (Items 9, 10)

#### [AccountScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt)
- Replace `AccountAvatarPlaceholder` with real avatar loaded from author dashboard.
- Display cached counts for Reading/Writing/Activity sections.

#### [AccountViewModel.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/account/AccountViewModel.kt)
- Fetch current user's profile on sign-in to populate avatar and counts.

## Verification Plan

### Automated Tests
- Run `AO3AuthorParserTest` (if exists) or create one.
- Run `EncryptedFileAO3SessionStoreTest` (if exists).
- Command: `./gradlew test`

### Manual Verification
- Log in using the new Native Login screen.
- Verify Author Profile tabs and pseud switching.
- Change a posting-pseud in a bookmark and verify it persists on AO3.
- Verify AO3 Preferences screen correctly saves a change.
- Check that the Account screen shows the real avatar after login.
