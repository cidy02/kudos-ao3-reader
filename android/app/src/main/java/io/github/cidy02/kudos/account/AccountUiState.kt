package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

data class AccountUiState(
    val authState: AO3AuthState = AO3AuthState.Restoring
)

/** Top segmented control on the Account hub (iOS SoT: Overview | Reading | Writing | Activity). */
enum class AccountHubTab(val label: String) {
    Overview("Overview"),
    Reading("Reading"),
    Writing("Writing"),
    Activity("Activity")
}

/** Reading-tab list picker options. */
enum class AccountReadingKind(val label: String) {
    MarkedForLater("Marked for Later"),
    Subscriptions("Subscriptions"),
    Bookmarks("Bookmarks"),
    Collections("Collections")
}

/** Writing-tab list picker options. Series/Drafts are stubs until AO3 list parsers exist. */
enum class AccountWritingKind(val label: String) {
    Works("Works"),
    Series("Series"),
    Drafts("Drafts")
}

/** Activity-tab list picker options. Inbox is a stub until an inbox API lands. */
enum class AccountActivityKind(val label: String) {
    History("History"),
    Inbox("Inbox")
}

sealed interface AccountListUiState {
    data object Loading : AccountListUiState
    data object AuthRequired : AccountListUiState
    data class Loaded(val page: AO3SearchPage) : AccountListUiState
    data class Failed(val message: String) : AccountListUiState
}

val AccountListUiState.works: List<AO3WorkSummary>
    get() = (this as? AccountListUiState.Loaded)?.page?.works.orEmpty()

sealed interface AO3CollectionsUiState {
    data object Loading : AO3CollectionsUiState
    data object AuthRequired : AO3CollectionsUiState
    data class Loaded(val collections: List<AO3Collection>) : AO3CollectionsUiState
    data class Failed(val message: String) : AO3CollectionsUiState
}

/** Resolve a work-list type for hub panes that load via [AccountListRepository]. */
fun AccountReadingKind.toAccountListType(): AccountListType? = when (this) {
    AccountReadingKind.MarkedForLater -> AccountListType.MarkedForLater
    AccountReadingKind.Subscriptions -> AccountListType.Subscriptions
    AccountReadingKind.Bookmarks -> AccountListType.Bookmarks
    AccountReadingKind.Collections -> null
}

fun AccountWritingKind.toAccountListType(): AccountListType? = when (this) {
    AccountWritingKind.Works -> AccountListType.MyWorks
    AccountWritingKind.Series, AccountWritingKind.Drafts -> null
}

fun AccountActivityKind.toAccountListType(): AccountListType? = when (this) {
    AccountActivityKind.History -> AccountListType.History
    AccountActivityKind.Inbox -> null
}
