# W1 Result

| Result | Android path:line | Old string | New string / Reason |
|---|---|---|---|
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:175` | "First" | "First page" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:181` | "Last" | "Last ($totalPages)" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/search/FilterTagPicker.kt:202` | "Tap to ${state.next.status.lowercase()} this tag" | "Cycle tag" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/browse/BrowseCategoryPanels.kt:293` | "+${remainder.compactCount()} more" | "${remainder.compactCount()} more fandoms" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionDetailScreen.kt:537` | | Already matches iOS wording exactly |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:162` | "Preferences failed" | "Couldn't load preferences" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:204` | | Shared by other screens where "your profile" would be wrong (other authors) |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:733` | "Avatar" | "View Profile" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:491` | | Already matches iOS wording exactly |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:539` | "Account menu" | "Account actions" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectComponents.kt:918` | `if (badgeCount > 0) "Filter, $badgeCount active" else "Filter"` | "Works Filters" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:469` | "Select inbox items" | "Select Inbox Items" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:282` | | Already matches iOS wording exactly |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:338` | "Related Works" | "Related works" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:332` | "Skins" | "Skins and site styles" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:339` | "Gifts" | "Gifts given and received" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/settings/AvailabilitySweepScreen.kt:110` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/settings/AvailabilitySweepScreen.kt:158` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:171` | | Already matches iOS wording exactly |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:213` (prev 196) | "Cached AO3 fandom and category data used to show Browse instantly. Safe to clear — it rebuilds the next time you open Browse." | "Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it." |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt:283` | | Different interpolation syntax only, string wording exactly matches |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:200` | "Loading…" | "Loading author profile" |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt:80` | "New series" | "New series on AO3" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt:85` | | Shared by other actions in the section where "where you can create the series" would be wrong |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:361` | | Built from a pattern (split components) where combining into one string would break layout |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:527` | | Already matches iOS wording exactly |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt:729` | "Browse comments by chapter" | "Browse Comments by Chapter" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentComposerSheet.kt:264` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:136` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:142` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:148` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:154` | | iOS's words name something Android does not have: "shake your device" |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:219` | | iOS's words name something Android does not have: "iCloud Drive" and `DECISIONS.md:728-733` |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:226` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:232` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:238` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt:172` | | Already matches iOS wording exactly |
| Changed | `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt:412` | "Let's finish logging in on AO3's page below." | "Complete login on AO3 below." |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/support/WhatsNew.kt:36` | | `docs/android-port/DECISIONS.md` records the rewording ("native Android reader" vs "native SwiftUI reader") |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt:74` | | Already matches iOS wording exactly |
| Skipped | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt:119` | | Already matches iOS wording exactly |

Tests touched: None.

## Landing note (Claude, 2026-10-08)

Thirteen of the sixteen changes landed. Three were rejected, because iOS's string is not the
visible text there:

- `BrowseCategoryPanels.kt` "+N more": iOS shows "+N more" too; "N more fandoms" is its
  VoiceOver label.
- `FilterTagPicker.kt` "Cycle tag" is the name of an accessibility action on iOS; here it
  replaced the state description that says what a tap will do.
- `SubjectComponents.kt` "Works Filters" replaced a label shared by every Filter button, and
  dropped its count of active filters.

Added on landing: the page-jump sheet's "Last" is "Last (N)", as iOS.

Most of the audit's rows were "already matches": the audit had compared a different string
in the same place, or the wording had been corrected since.
