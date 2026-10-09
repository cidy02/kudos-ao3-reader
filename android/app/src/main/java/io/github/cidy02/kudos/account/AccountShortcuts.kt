package io.github.cidy02.kudos.account

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.ui.graphics.vector.ImageVector

/** Only destinations Android can open natively. My series is not implemented yet. */
enum class AccountShortcut(val id: String, val title: String, val icon: ImageVector,
    val listType: AccountListType? = null) {
    Dashboard("dashboard", "Dashboard", Icons.Outlined.GridView),
    MarkedForLater("markedForLater", "Marked for Later", Icons.Outlined.Schedule, AccountListType.MarkedForLater),
    Bookmarks("bookmarks", "Bookmarks", Icons.Outlined.BookmarkBorder, AccountListType.Bookmarks),
    Collections("collections", "Collections", Icons.Outlined.Collections),
    Subscriptions("subscriptions", "Subscriptions", Icons.Outlined.NotificationsNone, AccountListType.Subscriptions),
    Works("works", "Works", Icons.Outlined.Description, AccountListType.MyWorks),
    Drafts("drafts", "Drafts", Icons.Outlined.EditNote),
    History("history", "History", Icons.Outlined.History, AccountListType.History),
    Inbox("inbox", "Inbox", Icons.Outlined.Inbox),
    Preferences("preferences", "Preferences", Icons.Outlined.Tune),
    MoreOnAO3("moreOnAO3", "More on AO3", Icons.Outlined.MoreHoriz)
}

/** Matches Swift's raw string, including empty/all-unknown restoring defaults. */
object AccountShortcutStore {
    const val key = "account.shortcuts"
    const val emptyFooter = "If you choose none, the grid is hidden. You can still find every destination in the sections below."
    val defaults = listOf(AccountShortcut.Dashboard, AccountShortcut.Subscriptions, AccountShortcut.Works,
        AccountShortcut.Bookmarks, AccountShortcut.Collections, AccountShortcut.History)

    fun decode(raw: String?): List<AccountShortcut> = raw.orEmpty().split(',')
        .mapNotNull { id -> AccountShortcut.entries.firstOrNull { it.id == id } }
        .ifEmpty { defaults }

    fun encode(shortcuts: List<AccountShortcut>): String = shortcuts.joinToString(",") { it.id }
}
