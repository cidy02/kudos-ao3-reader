package io.github.cidy02.kudos.core.model

import java.time.Instant
import java.util.UUID

data class Tag(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val dateCreated: Instant = Instant.now()
) {
    init {
        require(name.trim().isNotEmpty()) { "Tag name must not be blank." }
    }

    val normalizedName: String = name.trim()
}

data class Bookmark(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val urlString: String,
    val dateAdded: Instant = Instant.now()
)

data class WorkCollection(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val dateAdded: Instant = Instant.now(),
    val workIds: List<String> = emptyList(),
    val description: String? = null,
    val sortOrder: Int? = null
)

data class CustomFont(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val fileName: String,
    val dateAdded: Instant = Instant.now()
) {
    val selectionId: String
        get() = "custom:$fileName"
}

data class SavedSearch(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val dateAdded: Instant = Instant.now(),
    val filtersJson: String = "{}"
)
