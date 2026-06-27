package io.github.cidy02.kudos.account

enum class AccountListType(
    val title: String,
    val emptyTitle: String,
    val emptyMessage: String
) {
    MarkedForLater(
        title = "Marked for Later",
        emptyTitle = "Nothing marked for later",
        emptyMessage = "Works you mark for later on AO3 show up here."
    ),
    Bookmarks(
        title = "AO3 Bookmarks",
        emptyTitle = "No bookmarks yet",
        emptyMessage = "Works you bookmark on AO3 show up here."
    ),
    History(
        title = "AO3 History",
        emptyTitle = "No reading history",
        emptyMessage = "Works you read on AO3 show up here."
    ),
    Subscriptions(
        title = "Subscriptions",
        emptyTitle = "No subscriptions",
        emptyMessage = "Works you subscribe to on AO3 show up here."
    ),
    MyWorks(
        title = "My Works",
        emptyTitle = "No works yet",
        emptyMessage = "Works you post on AO3 show up here."
    )
}
