# R5: The 49 Differences in Behaviour, Sorted and Made Ready (A Reading)

Audit of section 3 ("B — both have it, and they differ") of `/Users/cidy02/kudos-android-lane/docs/android-port/audits/A14-result.md` (49 rows across 37 entries).
Both codebases were read as they stand on disk:
- iOS: `kudos-ao3-reader/` in this worktree
- Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`

---

## 1. Rows in Audit Order

### A9

#### **Go to page** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:343-345`
  ```swift
  Text("Go to page")
      .font(.system(size: headerTitleSize, weight: .semibold))
      .frame(maxWidth: .infinity, alignment: .leading)
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:156-178`
  ```kotlin
  Text(
      text = "$draftPage",
      lineHeight = 40.sp,
      style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.SemiBold)
  )
  Text(
      text = "of $totalPages",
      lineHeight = 20.sp,
      style = MaterialTheme.typography.bodyMedium,
      color = MaterialTheme.colorScheme.onSurfaceVariant
  )

  Slider(
      value = draft,
      onValueChange = { draft = it },
      valueRange = 1f..maxOf(totalPages, 2).toFloat(),
      modifier = Modifier.fillMaxWidth()
  )
  ```
- **Class**: **A** (deliberately Android: a continuous slider where iOS has a text field, with no "Go to page" title).

---

#### **Opens filters** (2 rows, the card's text and its `accessibilityHint`)
- **iOS now**: `kudos-ao3-reader/Features/Search/SearchResultsHero.swift:163-169`
  ```swift
  if let onEditFilters {
      Button(action: onEditFilters) { content }
          .buttonStyle(.plain)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(Text(spokenLabel))
          .accessibilityHint(Text("Opens filters"))
          .accessibilityAddTraits(.isButton)
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/search/SearchResultsHero.kt:120-122`
  ```kotlin
  modifier = modifier
      .fillMaxWidth()
      .then(if (onEditFilters != null) Modifier.clickable { onEditFilters() } else Modifier)
      .semantics { contentDescription = spoken }
  ```
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/search/SearchResultsHero.kt:121`
  - Old text: `if (onEditFilters != null) Modifier.clickable { onEditFilters() } else Modifier`
  - New text: `if (onEditFilters != null) Modifier.clickable(onClickLabel = "Opens filters") { onEditFilters() } else Modifier`
  - Property: `onClickLabel` (VoiceOver hint: "Opens filters").

---

#### **Fandom index** (2 rows, Label and `accessibilityLabel`)
- **iOS now**: `kudos-ao3-reader/Features/Search/FandomListView.swift:292-295`
  ```swift
  .accessibilityElement(children: .ignore)
  .accessibilityLabel("Fandom index")
  .accessibilityValue(indexedLetter ?? orderedAvailable.first ?? "No sections")
  .accessibilityAdjustableAction { direction in
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/browse/FandomListChrome.kt:356-376`
  ```kotlin
  Column(
      modifier
          .pointerInput(available) {
              fun pick(y: Float) {
                  val index = ((y / size.height.coerceAtLeast(1).toFloat()) * IndexLetters.size)
                      .toInt()
                      .coerceIn(IndexLetters.indices)
                  val letter = IndexLetters[index]
                  if (letter in available) onPick(letter)
              }
              awaitEachGesture {
                  val down = awaitFirstDown()
                  pick(down.position.y)
                  drag(down.id) { change ->
                      pick(change.position.y)
                      if (change.positionChange() != androidx.compose.ui.geometry.Offset.Zero) {
                          change.consume()
                      }
                  }
              }
          },
      horizontalAlignment = Alignment.CenterHorizontally
  )
  ```
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/browse/FandomListChrome.kt:357`
  - Old text: `modifier`
  - New text: `modifier.semantics { contentDescription = "Fandom index" }`
  - Property: `contentDescription`.

---

#### **No works with this tag match your filters.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:656-665`
  ```swift
  case .loaded where results.isEmpty && hasExtraFilters:
      // Over-filtered to nothing. AO3 searched the whole tag and found none,
      // so this is the real answer rather than "none on this page".
      ContentUnavailableView {
          Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
      } description: {
          Text("No works with this tag match your filters.")
      } actions: {
          Button("Clear Filters", action: resetFilters)
      }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/browse/TagWorksScreen.kt:198-202`
  ```kotlin
  } else if (current.page.works.isEmpty()) {
      EmptyStateCard(
          title = "No works found",
          message = "AO3 returned no works for this tag."
      )
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `TagWorksContent` (`android/app/src/main/java/io/github/cidy02/kudos/browse/TagWorksScreen.kt:198`), when `current.page.works.isEmpty()` and `filters != AO3TagFilter()`, display `EmptyStateCard(title = "No matching works", message = "No works with this tag match your filters.", primaryActionLabel = "Clear Filters", onPrimaryAction = { filters = AO3TagFilter() })`.

---

#### **AO3 has no works for this tag right now.** (2 rows, Text and description)
- **iOS now**: `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:666-671`
  ```swift
  case .loaded where results.isEmpty:
      ContentUnavailableView(
          "No works found",
          systemImage: "tag",
          description: Text("AO3 has no works for this tag right now.")
      )
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/browse/TagWorksScreen.kt:198-202`
  ```kotlin
  } else if (current.page.works.isEmpty()) {
      EmptyStateCard(
          title = "No works found",
          message = "AO3 returned no works for this tag."
      )
  }
  ```
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/browse/TagWorksScreen.kt:201`
  - Old text: `message = "AO3 returned no works for this tag."`
  - New text: `message = "AO3 has no works for this tag right now."`
  - Property: visible text (`message` parameter of `EmptyStateCard`).

---

### A10

#### **Collections footer.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/AO3CollectionsList.swift:382`
  ```swift
  Text("These are your AO3 collections. Collections you make in Kudos are in Library.")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionsScreen.kt:270`
  ```kotlin
  Text(
      text = "These are your AO3 collections...", fontSize = 13.sp,
      color = tokens.tertiaryInk,
      modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter)
  )
  ```
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionsScreen.kt:270`
  - Old text: `text = "These are your AO3 collections..."`
  - New text: `text = "These are your AO3 collections. Collections you make in Kudos are in Library."`
  - Property: visible text.

---

#### **Dashboard signed out.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/AO3DashboardView.swift:23-27`
  ```swift
  ContentUnavailableView {
      Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
  } description: {
      Text("Log in to AO3 to open your dashboard.")
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AO3DashboardScreen.kt:21-25`
  ```kotlin
  if (username.isNullOrBlank()) {
      // Sign in required state. iOS just shows the account logged out state, but we'll show empty.
      // Actually, username should be present if they are here.
      return
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AO3DashboardScreen` (`android/app/src/main/java/io/github/cidy02/kudos/account/AO3DashboardScreen.kt:21-25`), when `username.isNullOrBlank()`, instead of returning early, render `EmptyStateCard(title = "Not signed in", message = "Log in to AO3 to open your dashboard.")`.

---

#### **Couldn't load help.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:267-274`
  ```swift
  ContentUnavailableView {
      Label("Couldn't load help", systemImage: "exclamationmark.triangle")
  } description: {
      Text(message)
  } actions: {
      Button("Try Again") { openHelp(state.ref) }
      Button("Open on AO3") { router.open(state.ref.url) }
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:248-252`
  ```kotlin
  toggle.helpUrl?.let { helpUrl ->
      IconButton(onClick = { onOpenHelp(helpUrl) }) {
          Icon(Icons.Outlined.HelpOutline, contentDescription = "Help")
      }
  }
  ```
- **Class**: **F** (feature: in-app preference help fetching, parsing, sheet rendering, and error retry state).

---

#### **Session expired while saving preferences.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:486-489`
  ```swift
  } catch AO3Error.authenticationRequired {
      guard auth.sessionGeneration == expectedSessionGeneration else { return }
      banner = .error("Your AO3 session expired. Sign in again from Account.")
      await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration)
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:138-140`
  ```kotlin
  is AO3Result.Failure -> {
      status = "Save failed: ${result.error.displayMessage()}"
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AO3PreferencesScreen` save handler (`android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:138`), check if `result.error is AO3Error.AuthenticationRequired`; if so, set `status = "Your AO3 session expired. Sign in again from Account."` and trigger session expiration.

---

#### **Restoring AO3 session** (2 rows, Label and `accessibilityLabel`)
- **iOS now**: `kudos-ao3-reader/Features/Account/AccountComponents.swift:49-51`
  ```swift
  .padding(.vertical, 4)
  .skeletonShimmer()
  .accessibilityLabel("Restoring AO3 session")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:380-393, 580-584`
  ```kotlin
  if (authState is AO3AuthState.SignedIn) {
      AccountSignedInHeader(...)
  } else {
      AccountSignedOutHeader(authState = authState, onLogin = onLogin)
  }
  ```
  and `AccountSignedOutHeader` displays "Not signed in" for `AO3AuthState.Restoring`.
- **Class**: **S**
- **Smallest change**:
  In `AccountProfileHeader` (`android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:380`), add `else if (authState is AO3AuthState.Restoring)` to render a shimmering skeleton header box with `contentDescription = "Restoring AO3 session"` instead of `AccountSignedOutHeader`.

---

#### **Inbox page failed.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:544-549`
  ```swift
  statusRow(
      title: "Couldn't load page \(requestedPage)",
      systemImage: "exclamationmark.triangle",
      message: message,
      actionTitle: "Try Again"
  )
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxViewModel.kt:151-160` and `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:169-176`
  ```kotlin
  AlertDialog(
      onDismissRequest = viewModel::clearActionError,
      title = { Text("Couldn't update Inbox") },
      text = { Text(state.actionError ?: "AO3 couldn't update your Inbox.") },
      confirmButton = {
          TextButton(onClick = viewModel::clearActionError) { Text("OK") }
      }
  )
  ```
- **Class**: **F** (feature: multi-file state and UI flow in `AccountInboxViewModel`, `AccountInboxUiState`, and `AccountInboxPane` to preserve page 1 while showing an inline status error row for failed page transitions).

---

#### **Account Content** (2 rows, Label and `accessibilityLabel`)
- **iOS now**: `kudos-ao3-reader/Features/Account/AccountView.swift:332-338`
  ```swift
  SubjectSegmentedControl(
      options: AccountTab.allCases,
      title: \.rawValue,
      selection: $selectedTab
  )
  .accessibilityLabel("Account Content")
  .padding(.horizontal, SubjectMetrics.accountGutter)
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:236, 269, 290`
  ```kotlin
  item { AccountScopeGroup("Reading") { ... } }
  item { AccountScopeGroup("Writing") { ... } }
  item { AccountScopeGroup("Activity") { ... } }
  ```
- **Class**: **A** (deliberately Android: unified scrollable column of scope groups instead of a segmented control tab switcher).

---

#### **Profile unavailable** (2 rows, title and message)
- **iOS now**: `kudos-ao3-reader/Features/Account/AccountView.swift:727-733`
  ```swift
  case .unavailable:
      profileMessage(
          title: "Profile unavailable",
          systemImage: "person.slash",
          message: "AO3 could not load your profile. It may be temporarily unavailable.",
          layout: layout
      )
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:233-241`
  ```kotlin
  } else if (headerError != null && header == null) {
      item {
          ErrorStateCard(
              title = "Couldn't load author",
              message = headerError!!,
              primaryActionLabel = "Try Again",
              onPrimaryAction = { loadHeader() }
          )
      }
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AuthorProfileScreen` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:233`), when `isDashboard && headerError == "AO3 could not find that page."`, render `EmptyStateCard` with title "Profile unavailable" and message "AO3 could not load your profile. It may be temporarily unavailable." without a retry button.

---

#### **Clear Reading History button.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:125-129`
  ```swift
  Button("Clear \(countLabel(freedHistory.count, "Work"))", role: .destructive) {
      for work in freedHistory {
          PreservedWorkService.softDelete(work, in: context)
      }
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:188-193`
  ```kotlin
  confirmText = "Clear ${countLabel(historyOnlyWorks.size, "Work")}",
  confirmBeforeDelete = settings.app.confirmBeforeDelete,
  onConfirm = {
      showClearHistoryConfirm = false
      scope.launch { workRepository?.softDeleteHistoryOnly() }
  },
  ```
- **already the same**

---

#### **Clear Reading History message.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:132-134`
  ```swift
  Text("Moves works that only remain in your reading history to Recently Deleted for "
      + "\(PreservedWorkService.recoveryWindowText). Your saved and downloaded works "
      + "stay where they are, and you can download these works from AO3 again.")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:187`
  ```kotlin
  text = "Moves works that only remain in your reading history to Recently Deleted for 90 days. Your saved and downloaded works stay where they are, and you can download these works from AO3 again.",
  ```
- **already the same**

---

#### **Clear reading positions button.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:155-158`
  ```swift
  Button("Clear \(countLabel(positionedWorks.count, "Position"))", role: .destructive) {
      LocalDataClearing.clearReadingPositions(from: works, in: context)
      Task { await measure() }
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:201-205`
  ```kotlin
  confirmText = "Clear ${countLabel(positionedWorks.size, "Position")}",
  confirmBeforeDelete = settings.app.confirmBeforeDelete,
  onConfirm = {
      showClearPositionsConfirm = false
      scope.launch { workRepository?.clearReadingPositions() }
  },
  ```
- **already the same**

---

#### **Clear reading positions message.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:160`
  ```swift
  Text("Clears your place in every work. Your works and their order in Continue Reading stay the same.")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:200`
  ```kotlin
  text = "Clears your place in every work. Your works and their order in Continue Reading stay the same.",
  ```
- **already the same**

---

#### **Try Loading More.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:78-86`
  ```swift
  if let loadMoreError {
      VStack(alignment: .leading, spacing: 8) {
          Label(loadMoreError, systemImage: "exclamationmark.triangle")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          Button("Try Loading More", action: loadMore)
              .frame(minHeight: 44)
      }
      .cardRow()
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:386-394`
  ```kotlin
  } else if (tabError != null && page == 1) {
      item {
          ErrorStateCard(
              title = "Couldn't load ${tab.label.lowercase()}",
              message = tabError!!,
              primaryActionLabel = "Retry",
              onPrimaryAction = { loadTab(tab, page) }
          )
      }
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AuthorProfileScreen` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:426`), when `tabError != null && page > 1`, append a card row with `tabError` and button "Try Loading More" calling `loadTab(tab, page)` instead of hiding the failure.

---

#### **You have not made a series.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:484-487`
  ```swift
  VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
          Text("You have not made a series.")
              .font(.system(size: emptyTitleSize, weight: .semibold))
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:439-441`
  ```kotlin
  if (pageData != null && ownSeriesList) item {
      EmptyStateCard("You have not made a series.",
          "A series groups your works in reading order. Create one on AO3, then refresh this page to see it here.")
  ```
- **already the same**

---

#### **A series groups your works…** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:488-490`
  ```swift
  Text("A series groups your works in reading order. Create one on AO3, "
      + "then refresh this page to see it here.")
      .font(.system(size: emptyBodySize))
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:440-441`
  ```kotlin
  EmptyStateCard("You have not made a series.",
      "A series groups your works in reading order. Create one on AO3, then refresh this page to see it here.")
  ```
- **already the same**

---

#### **AO3 Profile alert.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:119-123`
  ```swift
  .alert("AO3 Profile", isPresented: actionMessagePresented) {
      Button("OK", role: .cancel) { model.clearActionMessage() }
  } message: {
      Text(model.actionMessage ?? "")
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:271-272`
  ```kotlin
  onSubscription = onOpenWeb,
  onModeration = { onOpenWeb(it.url) }
  ```
- **Class**: **F** (feature: native subscription/moderation scrape and post pipeline with dialog feedback titled "AO3 Profile").

---

#### **Log in to your AO3 account to do this.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:124-150`
  ```swift
  .alert("Log in to AO3", isPresented: $showingLoginRequired) {
      Button("Cancel", role: .cancel) { pendingAuthAction = nil }
      Button("Log In") { ... }
  } message: {
      Text("Log in to your AO3 account to do this.")
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:271`
  ```kotlin
  onSubscription = onOpenWeb,
  ```
- **Class**: **F** (feature: auth gating with login prompt before native profile mutations).

---

#### **Unsubscribing here applies to the whole AO3 account, not only this pseud.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:151-162`
  ```swift
  .confirmationDialog(
      "Unsubscribe from \(model.route.username)?",
      isPresented: $confirmingUnsubscribe,
      titleVisibility: .visible
  ) {
      Button("Unsubscribe", role: .destructive) {
          Task { await model.toggleSubscription(auth: auth) }
      }
      Button("Cancel", role: .cancel) {}
  } message: {
      Text("Unsubscribing here applies to the whole AO3 account, not only this pseud.")
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:271`
  ```kotlin
  onSubscription = onOpenWeb,
  ```
- **Class**: **F** (feature: native author subscription toggle and confirmation sheet).

---

#### **Author scope** (2 rows, Label and `accessibilityLabel`)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:409-421`
  ```swift
  } label: {
      HStack(spacing: 6) {
          Text(model.route.pseud ?? "All Pseuds")
              .lineLimit(1)
          Image(systemName: "chevron.up.chevron.down")
              .font(.caption2)
      }
      .foregroundStyle(.tint)
      .frame(minHeight: 44)
  }
  .accessibilityLabel("Author scope")
  .accessibilityValue(model.route.pseud ?? "All Pseuds")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:256-263, 280-288`
  ```kotlin
  LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      item {
          SubjectChip(text = "All Pseuds", style = SubjectChipStyle.Pill(route.pseud == null), modifier = Modifier.clickable { route = AO3AuthorRoute(route.username, null) })
      }
      items(h.pseuds) { pseud ->
          SubjectChip(text = pseud.name, style = SubjectChipStyle.Pill(route.pseud.equals(pseud.route.pseud, true)), modifier = Modifier.clickable { route = pseud.route })
      }
  }
  ```
- **Class**: **A** (deliberately Android: horizontal scrollable chip row instead of an iOS dropdown Menu button).

---

#### **Author unavailable** (2 rows, title and message)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:699-707`
  ```swift
  private var unavailableView: some View {
      ContentUnavailableView {
          Label("Author unavailable", systemImage: "person.slash")
      } description: {
          Text("AO3 could not find this user or pseud. It may have been renamed or deleted.")
      } actions: {
          Button("Open on AO3") { router.open(model.route.dashboardURL) }
      }
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:233-241`
  ```kotlin
  } else if (headerError != null && header == null) {
      item {
          ErrorStateCard(
              title = "Couldn't load author",
              message = headerError!!,
              primaryActionLabel = "Try Again",
              onPrimaryAction = { loadHeader() }
          )
      }
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AuthorProfileScreen` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:233`), when `headerError == "AO3 could not find that page."`, render `EmptyStateCard` with title "Author unavailable", message "AO3 could not find this user or pseud. It may have been renamed or deleted.", and action "Open on AO3" (`onOpenWeb`) instead of "Couldn't load author" / "Try Again".

---

#### **AO3 Author.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:728-740`
  ```swift
  private var failureHeader: some View {
      if usesAccountHeader {
          accountHeader
      } else {
          SubjectHeaderBlock(
              kicker: "AO3 Author",
              title: model.route.displayName,
              subtitle: model.route.pseud.map { _ in "Pseud of \(model.route.username)" },
              palette: theme.scopePalette,
              gutter: SubjectMetrics.accountGutter
          )
          .pageBodyRow(top: 16, gutter: 0)
      }
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:233-241`
  ```kotlin
  } else if (headerError != null && header == null) {
      item {
          ErrorStateCard(
              title = "Couldn't load author",
              message = headerError!!,
              primaryActionLabel = "Try Again",
              onPrimaryAction = { loadHeader() }
          )
      }
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AuthorProfileScreen` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:233`), render a header block above `ErrorStateCard` with kicker "AO3 Author", title `route.displayName`, and subtitle `"Pseud of ${route.username}"` when a non-404 profile header error occurs.

---

#### **Delete from history.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Bookmarks/AO3HistoryWorksBrowser.swift:139-148`
  ```swift
  .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if canDelete(entry) {
          Button(role: .destructive) {
              onDelete(entry)
          } label: {
              // 1t: names what is deleted — the history entry, not the work.
              Label("Delete from history", systemImage: "trash")
          }
      }
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:949-955`
  ```kotlin
  SubjectChip(
      text = "Delete",
      style = SubjectChipStyle.Neutral,
      leadingIcon = Icons.Outlined.Delete,
      palette = palette,
      modifier = Modifier.clickable(enabled = !busy) { pendingDelete = work }
  )
  ```
- **Class**: **A** (deliberately Android: a trailing swipe action that Android draws as an explicit inline action chip; backend delete to AO3 is already wired via `confirmDeleteReading`).

---

#### **Log in to AO3 to see your subscriptions.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift:239-241`
  ```swift
  } else {
      result = (requested, .failure(LoadFailure(message: "Log in to AO3 to see your subscriptions.")))
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:1271-1274`
  ```kotlin
  NamedSubscriptionsUiState.AuthRequired -> item {
      EmptyStateCard("AO3 session required", "Your AO3 session needs to be refreshed.",
          primaryActionLabel = "Log In Again", onPrimaryAction = onLogin)
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AccountWorksListScreen` (`android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:1271`), update `NamedSubscriptionsUiState.AuthRequired` to display `EmptyStateCard("Log in to AO3 to see your subscriptions.", "Your AO3 session needs to be refreshed.", primaryActionLabel = "Log In", onPrimaryAction = onLogin)`.

---

#### **Heading** (2 rows, Label and `accessibilityLabel`)
- **iOS now**: `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:476-490`
  ```swift
  ForEach(CommentMarkup.headingLevels, id: \.self) { level in
      Button {
          CommentMarkup.apply(
              .heading, text: &text, selection: &selection, headingLevel: level
          )
      } label: {
          SubjectChip(
              text: CommentMarkup.headingElement(level: level) ?? "",
              style: .neutral
          )
      }
      .buttonStyle(.plain)
      .minimumHitTarget()
      .accessibilityLabel("Heading \(level)")
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentMarkup.kt:83`
  ```kotlin
  Heading("Heading", "h3", Icons.Outlined.Title, TagGroup.Blocks, "<h3>", "</h3>"),
  ```
- **Class**: **S**
- **Smallest change**:
  In `CommentFormatBottomSheet` (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentMarkup.kt:239`), add a heading level picker for levels 1 through 6 that inserts `<h1>` through `<h6>`, with each level chip having `contentDescription = "Heading $level"`.

---

#### **You're offline. These comments are from {when}…** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Comments/CommentsView.swift:755-768`
  ```swift
  private var staleBanner: some View {
      Section {
          Label {
              let fetched = model.page?.fetchedAt
                  .formatted(.relative(presentation: .named)) ?? "earlier"
              Text("You're offline. These comments are from \(fetched) and may be out of date.")
          } icon: {
              Image(systemName: "wifi.exclamationmark")
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .cardRow()
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:58-60`
  ```kotlin
  if (useCache && public.error is AO3Error.Network && focusedCommentId == null) {
      cache?.load(target, safePage, viewer)?.let { return AO3Result.Success(it) }
  }
  ```
- **Class**: **F** (feature: multi-file cache metadata propagation from comment cache/repository into `CommentsViewModel` and a stale banner in `CommentsScreen`).

---

#### **View {author}'s profile, comment avatar** (2 rows, Label and `accessibilityLabel`)
- **iOS now**: `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1679-1681`
  ```swift
  .buttonStyle(.plain)
  .accessibilityLabel("View \(comment.author)'s profile")
  .accessibilityHint("Opens author profile")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:427-434`
  ```kotlin
  Box(
      modifier = Modifier
          .size(avatarSize)
          .then(
              if (comment.author.username != null) {
                  Modifier.clickable { handlers.onOpenAuthor(comment.author.username) }
              } else Modifier
          )
  ) {
  ```
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:432`
  - Old text: `Modifier.clickable { handlers.onOpenAuthor(comment.author.username) }`
  - New text: `Modifier.clickable(onClickLabel = "Opens author profile") { handlers.onOpenAuthor(comment.author.username) }.semantics { contentDescription = "View ${comment.author.displayName}'s profile" }`
  - Properties: `contentDescription` (for VoiceOver label "View {author}'s profile") and `onClickLabel` (for VoiceOver hint "Opens author profile").

---

#### **View {author}'s profile, composer byline** (2 rows, Label and `accessibilityLabel`)
- **iOS now**: `kudos-ao3-reader/Features/Comments/CommentsView.swift:1463-1465`
  ```swift
  .buttonStyle(.plain)
  .accessibilityLabel("View \(parent.author)'s profile")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentComposerSheet.kt:178-186`
  ```kotlin
  Text(
      text = replyTarget.author.name,
      fontSize = 12.sp,
      fontWeight = FontWeight.SemiBold,
      color = palette.accent,
      modifier = Modifier.clickable {
          replyTarget.author.username?.let(onOpenAuthor)
      }
  )
  ```
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentComposerSheet.kt:183-185`
  - Old text:
    ```kotlin
    modifier = Modifier.clickable {
        replyTarget.author.username?.let(onOpenAuthor)
    }
    ```
  - New text:
    ```kotlin
    modifier = Modifier
        .clickable { replyTarget.author.username?.let(onOpenAuthor) }
        .semantics { contentDescription = "View ${replyTarget.author.name}'s profile" }
    ```
  - Property: `contentDescription`.

---

#### **We're checking whether this posted before trying again…** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Comments/CommentsView.swift:1497-1502`
  ```swift
  switch model.submissionGuard.phase {
  case .verifying:
      Label("We're checking whether this posted before trying again…",
            systemImage: "clock.arrow.circlepath")
          .font(.footnote)
          .foregroundStyle(.secondary)
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:400-403, 437-442`
  ```kotlin
  if (contentHash == lastSubmittedContentHash) {
      _message.value = "You just posted this. Reload to see if it appeared."
      return
  }
  ```
- **Class**: **F** (feature: 2-phase post submission verification guard state machine and persistent status banner).

---

#### **Check Again.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Comments/CommentsView.swift:1508-1516`
  ```swift
  // Re-posting stays blocked until a check definitively answers —
  // this re-runs the verification fetch, never the POST.
  Button {
      Task { await model.reverify(auth: auth) }
  } label: {
      Label("Check Again", systemImage: "arrow.clockwise")
          .font(.footnote.weight(.medium))
  }
  .buttonStyle(.bordered)
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:437-444` (no reverification button or state exists).
- **Class**: **F** (feature: non-POST comment reverify check button and handler).

---

#### **Posted.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Comments/CommentsView.swift:1522-1525`
  ```swift
  case .succeeded:
      Label("Posted.", systemImage: "checkmark.circle")
          .font(.footnote)
          .foregroundStyle(.green)
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:168`
  ```kotlin
  AO3WriteOutcome(
      AO3WriteActionKind.Comment,
      if (replyParentId != null) "Reply posted." else "Comment posted."
  )
  ```
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:168`
  - Old text: `if (replyParentId != null) "Reply posted." else "Comment posted."`
  - New text: `"Posted."`
  - Property: visible text.

---

#### **No works on this page match the current filters.** (1 row)
- **iOS now**: `kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:712-721`
  ```swift
  } else if visibleWorks.isEmpty, !works.isEmpty {
      // Everything on the page was filtered out by the refine facets.
      ContentUnavailableView {
          Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
      } description: {
          Text("No works on this page match the current filters.")
      } actions: {
          Button("Clear Filters") { filters = AO3SearchFilters() }
      }
  }
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:718-728`
  ```kotlin
  if (displayedWorks.isEmpty()) {
      item {
          EmptyStateCard(
              title = "No matching works",
              message = when (filter) {
                  "recs" -> "No works on this page are recommended."
                  "private" -> "No works on this page are private."
                  "withNotes" -> "No works on this page have notes."
                  else -> "No works on this page."
              }
          )
      }
  }
  ```
- **Class**: **S**
- **Smallest change**:
  In `AccountWorksListScreen` (`android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:718`), when `activeWorks.isNotEmpty() && displayedWorks.isEmpty()`, show `EmptyStateCard(title = "No matching works", message = "No works on this page match the current filters.", primaryActionLabel = "Clear Filters", onPrimaryAction = { filter = "all" })`.

---

### A11

#### **Double-tap to select this work. / Double-tap to deselect this work.** (2 rows, the two branches of one hint)
- **iOS now**: `kudos-ao3-reader/Features/Privacy/MatureContent.swift:194-196`
  ```swift
  .accessibilityLabel("Hidden mature work")
  .accessibilityValue(isSelected ? "Selected" : "Not selected")
  .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
  ```
- **Android now**: `android/app/src/main/java/io/github/cidy02/kudos/ui/components/SensitiveWorkRow.kt:69-72` and `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectWorkCoverCard.kt:547-551`
  ```kotlin
  fun Modifier.hiddenMatureWorkSemantics(obscured: Boolean, selecting: Boolean = false): Modifier =
      if (!obscured) this else clearAndSetSemantics {
          contentDescription = if (selecting) "Hidden mature work" else "Hidden mature work. Activate to reveal."
      }
  ```
  and `SelectionChrome` has `contentDescription = "Selected"` only when checked.
- **Class**: **L**
- **Exact edit**:
  - `android/app/src/main/java/io/github/cidy02/kudos/ui/components/SensitiveWorkRow.kt:70-72`
  - Old text:
    ```kotlin
    if (!obscured) this else clearAndSetSemantics {
        contentDescription = if (selecting) "Hidden mature work" else "Hidden mature work. Activate to reveal."
    }
    ```
  - New text:
    ```kotlin
    fun Modifier.hiddenMatureWorkSemantics(obscured: Boolean, selecting: Boolean = false, isSelected: Boolean = false): Modifier =
        if (!obscured) this else clearAndSetSemantics {
            contentDescription = if (selecting) "Hidden mature work" else "Hidden mature work. Activate to reveal."
            if (selecting) {
                stateDescription = if (isSelected) "Selected" else "Not selected"
                onClickLabel = if (isSelected) "Deselect this work" else "Select this work"
            }
        }
    ```
  - Properties: `stateDescription` (VoiceOver value "Selected" / "Not selected") and `onClickLabel` (VoiceOver hint "Double-tap to select this work." / "Double-tap to deselect this work.").

---

## 2. Table of Every Row

| # | Row Title | Class | One-Line Edit (for L rows) / Status |
|---|---|:---:|---|
| 1 | **Go to page** | **A** | Platform control: continuous `Slider` where iOS uses a number field. |
| 2 | **Opens filters** (card text) | **L** | `search/SearchResultsHero.kt:121`: add `onClickLabel = "Opens filters"` to `clickable`. |
| 3 | **Opens filters** (`accessibilityHint`) | **L** | `search/SearchResultsHero.kt:121`: add `onClickLabel = "Opens filters"` to `clickable`. |
| 4 | **Fandom index** (Label) | **L** | `browse/FandomListChrome.kt:357`: add `.semantics { contentDescription = "Fandom index" }`. |
| 5 | **Fandom index** (`accessibilityLabel`) | **L** | `browse/FandomListChrome.kt:357`: add `.semantics { contentDescription = "Fandom index" }`. |
| 6 | **No works with this tag match your filters.** | **S** | Empty state when `current.page.works.isEmpty()` with active filters in `TagWorksScreen.kt`. |
| 7 | **AO3 has no works for this tag right now.** (Text) | **L** | `browse/TagWorksScreen.kt:201`: replace `"AO3 returned no works for this tag."` with `"AO3 has no works for this tag right now."`. |
| 8 | **AO3 has no works for this tag right now.** (description) | **L** | `browse/TagWorksScreen.kt:201`: replace `"AO3 returned no works for this tag."` with `"AO3 has no works for this tag right now."`. |
| 9 | **Collections footer.** | **L** | `account/AO3CollectionsScreen.kt:270`: replace `"These are your AO3 collections..."` with `"These are your AO3 collections. Collections you make in Kudos are in Library."`. |
| 10 | **Dashboard signed out.** | **S** | Render `EmptyStateCard` instead of early return when username is blank in `AO3DashboardScreen.kt`. |
| 11 | **Couldn't load help.** | **F** | In-app help fetch, parse, and sheet error recovery in `AO3PreferencesScreen.kt`. |
| 12 | **Session expired while saving preferences.** | **S** | Handle `AuthenticationRequired` with expiration message and trigger in `AO3PreferencesScreen.kt`. |
| 13 | **Restoring AO3 session** (Label) | **S** | Render restoring skeleton header for `AO3AuthState.Restoring` in `AccountScreen.kt`. |
| 14 | **Restoring AO3 session** (`accessibilityLabel`) | **S** | Set `contentDescription = "Restoring AO3 session"` on restoring skeleton header in `AccountScreen.kt`. |
| 15 | **Inbox page failed.** | **F** | Multi-file pagination failure state and inline status row in `AccountInboxViewModel.kt` and `AccountInboxPane.kt`. |
| 16 | **Account Content** (Label) | **A** | Platform layout: unified scrolling group sections instead of segmented control tab switcher. |
| 17 | **Account Content** (`accessibilityLabel`) | **A** | Platform layout: unified scrolling group sections instead of segmented control tab switcher. |
| 18 | **Profile unavailable** (title) | **S** | Show "Profile unavailable" for 404 in `AuthorProfileScreen.kt` when `isDashboard`. |
| 19 | **Profile unavailable** (message) | **S** | Show "AO3 could not load your profile..." for 404 in `AuthorProfileScreen.kt`. |
| 20 | **Clear Reading History button.** | — | **already the same** (`PrivacyDataScreen.kt:188`). |
| 21 | **Clear Reading History message.** | — | **already the same** (`PrivacyDataScreen.kt:187`). |
| 22 | **Clear reading positions button.** | — | **already the same** (`PrivacyDataScreen.kt:201`). |
| 23 | **Clear reading positions message.** | — | **already the same** (`PrivacyDataScreen.kt:200`). |
| 24 | **Try Loading More.** | **S** | Render inline error row with "Try Loading More" button on `page > 1` in `AuthorProfileScreen.kt`. |
| 25 | **You have not made a series.** | — | **already the same** (`AuthorProfileScreen.kt:440`). |
| 26 | **A series groups your works…** | — | **already the same** (`AuthorProfileScreen.kt:441`). |
| 27 | **AO3 Profile alert.** | **F** | Native author action network form POST and alert presentation in `AuthorProfileScreen.kt`. |
| 28 | **Log in to your AO3 account to do this.** | **F** | Auth gating and login prompt before author action in `AuthorProfileScreen.kt`. |
| 29 | **Unsubscribing here applies to the whole AO3 account...** | **F** | Native author unsubscription confirmation dialog in `AuthorProfileScreen.kt`. |
| 30 | **Author scope** (Label) | **A** | Platform control: `LazyRow` chip strip instead of dropdown `Menu`. |
| 31 | **Author scope** (`accessibilityLabel`) | **A** | Platform control: `LazyRow` chip strip instead of dropdown `Menu`. |
| 32 | **Author unavailable** (title) | **S** | Show "Author unavailable" for 404 in `AuthorProfileScreen.kt`. |
| 33 | **Author unavailable** (message) | **S** | Show "AO3 could not find this user or pseud..." for 404 in `AuthorProfileScreen.kt`. |
| 34 | **AO3 Author.** | **S** | Add `SubjectHeaderBlock` with kicker "AO3 Author" above failure card in `AuthorProfileScreen.kt`. |
| 35 | **Delete from history.** | **A** | Platform control: trailing swipe action drawn as an inline `SubjectChip`. |
| 36 | **Log in to AO3 to see your subscriptions.** | **S** | Empty state copy for `NamedSubscriptionsUiState.AuthRequired` in `AccountWorksListScreen.kt`. |
| 37 | **Heading** (Label) | **S** | Replace fixed `h3` with `h1`..`h6` heading level chips in `CommentMarkup.kt`. |
| 38 | **Heading** (`accessibilityLabel`) | **S** | Set `contentDescription = "Heading $level"` on heading level chips in `CommentMarkup.kt`. |
| 39 | **You're offline. These comments are from {when}…** | **F** | Multi-file cache metadata propagation and stale comment banner in `CommentsScreen.kt`. |
| 40 | **View {author}'s profile, comment avatar** (Label) | **L** | `comments/CommentThreadComponents.kt:432`: add `contentDescription = "View ${comment.author.displayName}'s profile"`. |
| 41 | **View {author}'s profile, comment avatar** (`accessibilityLabel`) | **L** | `comments/CommentThreadComponents.kt:432`: add `onClickLabel = "Opens author profile"`. |
| 42 | **View {author}'s profile, composer byline** (Label) | **L** | `comments/CommentComposerSheet.kt:183`: add `contentDescription = "View ${replyTarget.author.name}'s profile"`. |
| 43 | **View {author}'s profile, composer byline** (`accessibilityLabel`) | **L** | `comments/CommentComposerSheet.kt:183`: add `contentDescription = "View ${replyTarget.author.name}'s profile"`. |
| 44 | **We're checking whether this posted before trying again…** | **F** | Multi-phase asynchronous comment post verification state in `CommentsViewModel.kt`. |
| 45 | **Check Again.** | **F** | Reverify check action and button in comment post verification flow. |
| 46 | **Posted.** | **L** | `network/ao3/comments/AO3CommentRepository.kt:168`: replace `"Reply posted."` / `"Comment posted."` with `"Posted."`. |
| 47 | **No works on this page match the current filters.** | **S** | Empty state when `activeWorks.isNotEmpty() && displayedWorks.isEmpty()` in `AccountWorksListScreen.kt`. |
| 48 | **Double-tap to select this work.** | **L** | `ui/components/SensitiveWorkRow.kt:71`: add `onClickLabel = "Select this work"` and `stateDescription = "Not selected"`. |
| 49 | **Double-tap to deselect this work.** | **L** | `ui/components/SensitiveWorkRow.kt:71`: add `onClickLabel = "Deselect this work"` and `stateDescription = "Selected"`. |

---

## 3. Counts per Class

| Class | Meaning | Count |
|---|---|---:|
| **—** | Already the same (resolved on Android) | 6 |
| **L** | Label or words only (`contentDescription`, `onClickLabel`, `stateDescription`, visible text) | 14 |
| **S** | Small difference in control behavior contained in one function or composable | 15 |
| **F** | Feature (screen, sheet, network scrape/write, or change across several files) | 8 |
| **A** | Deliberately Android (platform control: slider, chip row, scrollable group, inline chip) | 6 |
| **Total** | | **49** |

## Triage (Claude, 2026-10-09, first pass)

A reading of A14's 49 "both have it, and they differ" rows against today's code: 6 already
the same, 14 label-only, 15 small, 8 features, 6 deliberately Android.

**The 14 label rows are applied** (eight edits, each checked against iOS's string first):

- Search's summary card says what a tap does ("open filters"; iOS's hint is "Opens
  filters", worded here as TalkBack completes "Double-tap to …").
- The fandom list's letter strip is named "Fandom index". It is still pointer-only: iOS
  also makes it adjustable. That is one of the small rows, not done.
- A tag page with no works says "AO3 has no works for this tag right now."
- **The AO3 Collections footer read "These are your AO3 collections..." with the three dots
  in the code**: a sentence left unfinished. It has iOS's whole sentence now.
- A comment's avatar and the composer's byline are named "View {author}'s profile".
- A posted comment or reply says "Posted.", iOS's one word (two tests updated).
- A work row in Select mode says what a tap does ("select this work", "deselect this work").

Not seen on a device with TalkBack.

Still to do: the 15 small rows and the 8 feature rows (the cached-comments banner, the
"checking whether this posted" flow and "Check Again", the heading level chips among them).
