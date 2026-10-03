# Screen inventory (LOOP-v3, iPhone)

Artboard ids and labels: `artboards.tsv`. Debug routes: `library | browse | account | search |
section:<kind> | queues | queue:<name> | work:<title> | mycopy:<title> | comments` (+ `-library.dashboard.layout ledger`).
"harness" = needs a DEBUG sample-data route before it can be screenshotted offline.

Status columns:
- **C** = Claude audit;
- **X** = external audit (agent);
- **F** = accepted findings fixed;
- **S** = screenshot matches the spec.

Mark each `–` (not yet), `✓` or `n/a`.

## B1 — Home & Library dashboards and section lists (external: Codex)
| Screen | Swift | Artboards | Route | C | X | F | S |
|---|---|---|---|---|---|---|---|
| Home dashboard | HomeView, HomeResumeHero, HomeCollectionShelves | 1b | (default) | ✓ | – | – | ✓ |
| Library dashboard (shelves / ledger) | LibraryView, WorkCarouselSection, WorkLedgerListSection | 1c, 1d | library | ✓ | – | – | ✓ |
| Home section list | HomeSectionListView | 1ad, 1ae | harness | ✓ | – | ✓ T-314 | ✓ |
| Library section list (Reading Now, Saved for Later, Finished, Downloaded) | LibrarySectionListView | 1ad, 1ay | section:readingNow | ✓ | – | ✓ | ✓ |
| Reading History | LibrarySectionListView (+Grouping, FactsStrip) | 1ah | section:history | ✓ | – | ✓ | ✓ |
| Favorites (works/authors/fandoms/tags) | LibrarySectionListView, FavoriteAffinityRow | 1aj, 1bc, 1bd | section:favorites | ✓ (works) | – | – | ✓ (works) |
| Library filter panel | LibraryFilterPanel | (1an style) | library → Filter | ✓ | – | ✓ T-324 | ✓ |

## B2 — Reading queues (external: Grok)
| Queues organizer | ReadingQueueOrganizer | 1i | queues | ✓ | ✓ (Grok B2) | ✓ df43b534 | ✓ |
|---|---|---|---|---|---|---|---|
| New queue sheet | NewReadingQueueSheet | 1j | queues → + | – | ✓ Codex t12 | rejected (28pt rule) | – |
| Queue page list/grid, select mode | ReadingQueueBrowser, ReadingQueuePageParts | 1h, 1bg | queue:Slow burns | ✓ | ✓ (Grok B2) | ✓ T-299 | ✓ |
| Queue settings | ReadingQueueSettingsView | 1h (details) | queue-details:Slow burns | ✓ | ✓ (Grok B2) | ✓ T-312 | ✓ |
| Queue tags / tag manager | QueueTagSheet, QueueTagManagerView | Shared queue — tag manager, Tag manager — rename and merge | queue → tags | ✓ | ✓ (Grok B2) | ✓ T-299/T-312 | – |
| Queue switcher | ReadingQueueSwitcher | 1h | queue → pill | – | ✓ Codex t12 | none | – |

## B3 — Work detail & comments (Claude)
| Work detail | WorkDetailView (+Identity, Overview, Facts, Sections) | 1a | work:<title> | ✓ (top + facts) | – | ✓ | ✓ (top) |
|---|---|---|---|---|---|---|---|
| My copy sheet | WorkDetailView.myCopySheet, WorkDetailSections, WorkProvenanceSections | 1a | mycopy:<title> | ✓ | – | ✓ | ✓ |
| Add to queue / collection sheets | AddToQueueView, AddToCollection… | — | work → My copy | – | ✓ Codex t12 | OD #2 | – |
| Comments | CommentsView, CommentThreadRow | 1f | comments (rows only) | ✓ | – | – | – |
| Comment composer, formatting tray | CommentComposerSheet, CommentMarkup | 1ba, 1be, 1bf | harness | ✓ code | ✓ Codex t12 | ✓ T-329 | – composer not reachable offline |
| Thread screen | CommentThreadScreen | 1f | harness | ✓ code | ✓ Codex t12 | ✓ T-329 | – not reachable offline |

## B4 — Browse & Search
| Browse (media → fandom clusters) | NativeBrowseView, MediaBrowserView | 1g | browse | ✓ | – | ✓ T-321 | ✓ |
|---|---|---|---|---|---|---|---|
| Fandom list (entries, families, filter) | FandomListView, FandomListFilterSheet, FandomFamilyRows | 1al, 1am, 1an | harness | ✓ | ✓ Codex t12 | ✓ T-329 (A–Z index, row indicators open) | ✓ Most works + A–Z |
| Fandom works / tag works | NativeBrowseView (fandom, tag) | 1k | harness | ✓ | – | ✓ T-322 | ✓ |
| Search + results + paging | SearchView, SearchResultsHero, SearchPaginationBar | 1k (paging pill, page sheet) | search, tagsearch:<fandom> | ✓ | – | ✓ T-322 | ✓ |
| Filters (AO3 filter panel, ranges, language, tag picker, refine) | AO3FilterPanel, FilterRangeSlider, FilterLanguagePicker, TagSelectField, AO3SummaryFilter | 1ao–1aw | search → Filter | ✓ (panel) | – | n/a | ✓ (panel) |
| Save search | SaveSearchSheet | 1ax | search → save | ✓ code | ✓ Codex t12 | ✓ T-328/329 | – needs filters set |

## B5 — Account hub, reading scopes, inbox
| Account hub (signed in / out) | AccountView, AccountComponents, AccountShortcuts | 1m, 1n, Account — Reading/Activity/Writing scope | account | ✓ | ✓ (Grok B5) | ✓ T-315 | ✓ |
| Marked for Later | AO3MarkedForLaterWorksBrowser, AO3AccountWorksList | 1o | acct:later | ✓ | – | – (L3-B5-20/21 open) | – |
| Bookmarks | AO3BookmarksWorksBrowser | 1q | acct:bookmarks | ✓ | – | ✓ T-313 | ✓ |
| History (AO3) | AO3HistoryWorksBrowser | 1t | harness | ✓ code | ✓ Codex t12 | ✓ T-328 (layout → OD #10) | – |
| Subscriptions (works / series / users) | AO3SubscriptionsWorksBrowser, AO3NamedSubscriptionsList | 1p, 1ag | acct:subscriptions | ✓ | ✓ (Grok B5) | ✓ T-317 (+OD #5) | – |
| Inbox + filter sheet | AccountInboxScreen, AccountInboxViews, AccountInboxFilterSheet | 1l | acct:inbox | ✓ | ✓ (Grok B5) | ✓ T-318 | ✓ |
| Dashboard (own works stats) | AO3DashboardView | 1y | acct:dashboard | ✓ | ✓ (Grok B5) | ✓ T-316 | ✓ |

## B6 — AO3 collections
| AO3 collections list + sort/filter | AO3CollectionsList, AO3CollectionsFilterPanel | 1r, 1bm | acct:collections | ✓ | – | n/a | ✓ |
|---|---|---|---|---|---|---|---|
| AO3 collection detail | AO3CollectionDetailView | 1ci | acct:ao3collection:fest | ✓ | – | ✓ L3-FORM-1 | ✓ |
| Collection items (manage) | AO3CollectionItemsView | 1s | Moderation → Recently decided (AXe tap) | ✓ | ✓ Codex t10 | ✓ T-326/327 | ✓ |
| AO3 collection new / edit / delete | AO3CollectionFormView | AO3 collection — new/edit/delete confirmation | harness | ✓ code | ✓ Codex t10 | OD #9 | ✓ Edit collection (T-326 shots) |

## B7 — Writing & author profile
| Author profile (Works, Series, About, dashboard) | AuthorProfileView, AuthorProfile*Sections, WorksScopeAndSort | 1u, 1v, 1w, 1y | harness | ✓ | ✓ Codex t12 | ✓ T-328/329 | ✓ Dashboard ledger + detailed, Works |
| Series detail | AO3SeriesDetailView | 1w (1az = empty own-Series state on the author page) | harness | ✓ code | ✓ Codex t12 | n/a | – |
| Work Edit (+ delete) | WorkEditView | Work Edit, Work Edit — delete confirmation | acct:workedit:<id> | ✓ | – | ✓ L3-FORM-1 | ✓ |
| Edit Tags / tag picker | EditTagsView, WritingTagsEditor | 1bp, Tag picker — typing/chosen | harness | – (no route) | – | ✓ L3-FORM-1 | – |
| Add Chapter / chapters | AddChapterView, WritingChaptersView | 1bq | harness | ✓ code | – | ✓ L3-FORM-1 | – needs chapter-form fixture |
| Chapter text editor, preview | WritingTextEditor, WritingNativeTextView, WritingPreviewView | 1bv | harness | ✓ code | ✓ agy t14 | ✓ T-331 (1bv toolbar open) | – |
| Drafts (+ post/delete confirmations) | WritingDraftsView | 1x, Draft editor/post/delete | harness | ✓ code | ✓ agy t14 | ✓ T-331 | – |
| Series edit / reorder | SeriesEditView, SeriesReorderDestination | Series Edit, Series Reorder | acct:seriesedit | ✓ | – | ✓ T-320 + L3-FORM-1 | ✓ |
| Collections & gifts / series pickers | WorkAssociationPickers | Collections and gifts, Series picker | harness | ✓ code | ✓ agy t14 | ✓ T-331 | – |
| Edit Multiple Works, bulk tags, own-works select | EditMultipleWorksView, BulkTagStatePicker, OwnWorksBulkBar | Edit Multiple Works, Works — select mode | harness | ✓ code | – | ✓ L3-FORM-1 | – |

## B8 — Challenges & moderation
| Sign-ups, your sign-up, assignments | ChallengeSignUpsView, ChallengeSignUpView, ChallengeAssignmentsView | 1bz, 1ca, 1cb | `acct:ao3collection:winter_exchange` + `-KudosDebugManageRow <row>` | ✓ assignments | ✓ Codex t10 | ✓ T-327 | ✓ assignments; sign-ups pending |
|---|---|---|---|---|---|---|---|
| Prompt meme, prompt tags | PromptMemeView, PromptTagsEditorView | 1cc | no fixture (`/requests`) | ✓ | ✓ Codex t10 | ✓ T-326/331 | ✓ 1cc (fixture T-331) |
| Moderation (+ reject reason), maintainers | CollectionModerationView, CollectionMaintainersView | 1cd, 1ce, Collection maintainers, Moderated items | `acct:ao3collection:winter_exchange` + `-KudosDebugManageRow <row>` | ✓ | ✓ Codex t10 | ✓ T-327 | ✓ |
| Challenge / collection settings (+ edit) | ChallengeSettingsView, ChallengeSettingsEditView | 1cf, 1cg, 1by | `acct:ao3collection:winter_exchange` + `-KudosDebugManageRow <row>` "Challenge Settings" | ✓ 1by | ✓ Codex t10 | ✓ T-326 | ✓ 1by; edit pending |
| Tag set | TagSetView | 1ch | "Challenge Settings" row → Tag set (AXe tap) | ✓ | ✓ Codex t10 | ✓ T-326/327 | ✓ (counts: L3-B8-5) |

## B9 — Library extras
| Local collection page (+ details, reorder) | Collections.swift (CollectionDetailView), NewCollectionSheet (CollectionReorderSheet) | Local collection — new/edit | library → Collections | ✓ | – | n/a | ✓ |
|---|---|---|---|---|---|---|---|
| New collection sheet | NewCollectionSheet | Local collection — new | library → + | ✓ | ✓ agy t14 | ✓ T-331 (L3-B1-9) | ✓ |
| Collections See All grid | LibraryEntityGridView | — | collections | ✓ | – | ✓ T-308/T-310 | ✓ |
| Add works sheet | AddLibraryWorksSheet | — | collection:<name> → Add Works (AXe) | ✓ | – | L3-B1-10 open | ✓ |
| Reading Insights | ReadingInsightsView | 1bi | library → … → Insights | ✓ (B9) | – | ✓ T-319 | ✓ (insights route) |
| Recently Deleted (+ permanent delete) | RecentlyDeletedView | Recently Deleted, … — permanent delete | library → Recently Deleted | ✓ (B9) | – | ✓ L3-B9-2 | ✓ (recentlyDeleted route) |

## B10 — Settings, privacy, preferences, onboarding, support
| Settings hub + pages (reading, storage, backup, import, sync folder, account) | SettingsHubView, SettingsView, Settings*Page(s) | Settings | acct:settings | ✓ (hub) | – | ✓ L3-B10-1 | ✓ (hub) |
|---|---|---|---|---|---|---|---|
| Privacy and local data | PrivacyDataView | Privacy and local data | account → Settings | ✓ | ✓ agy t14 | ✓ T-330 | ✓ |
| AO3 Preferences (+ saved) | AO3PreferencesView | 1z, 1bb | acct:preferences | ✓ | – | n/a | ✓ |
| More on AO3 | AccountMoreOnAO3View | More on AO3 | acct:more | ✓ | – | n/a | ✓ |
| Login | AO3LoginView | 1n | account (signed out) | ✓ code | ✓ agy t14 | none | – not opened (AO3 web view) |
| Onboarding, sync-folder onboarding | WelcomeView, SyncFolderOnboardingView | — | fresh launch | – | ✓ agy t14 | none | – |
| About, legal, bug report, what's new, backup import, pairing | AboutView, LegalNoticesView, BugReportView, WhatsNew, BackupImportSheet, PairingSheet | — | settings | – | ✓ agy t14 | OD #2 (checkmark) | – |
| Availability sweep | AvailabilitySweepView | — | settings | ✓ code | ✓ agy t14 | ✓ T-330 (Form+cardRow open) | – |

## B11 — Reader (no artboards: consistency, HIG, a11y only)
| Reader + chrome, position card, scrub | ReadiumReaderView, ReaderChromeTopBar, ReaderPositionCard, ReaderChapterScrub | — | read:<title> | ✓ (page; chrome needs taps) | – | OD #6 | ✓ (page) |
| Contents, search, notes | ReaderContentsSheet, ReaderSearchView, ReaderNoteEditor | — | reader | ✓ code | ✓ agy t14 | ✓ T-330 | – reader not screenshotted |
| Speech settings, pronunciation, fan menu, theme | ReaderSpeechSettingsSheet, ReaderPronunciationSettingsView, ReaderFanMenu, CustomizeThemeView | — | reader | ✓ code | ✓ agy t14 | ✓ T-330 | – |
