package io.github.cidy02.kudos.network.ao3.comments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-function tests for participant-role resolution and avatar URL helpers.
 * Ports the decision order of iOS `AO3CommentParticipantRole.resolve`.
 */
class AO3CommentParticipantRoleTest {
    @Test
    fun meWinsOverAuthorWhenSignedInCreatorComments() {
        val role = AO3CommentParticipantRole.resolve(
            name = "Author Pseud",
            isGuest = false,
            commenterUsername = "creator",
            currentUsername = "creator",
            workAuthors = listOf("Author Pseud"),
            workAuthorUsernames = listOf("creator")
        )
        assertEquals(AO3CommentParticipantRole.Me, role)
    }

    @Test
    fun anonymousCreatorIsAuthor() {
        val role = AO3CommentParticipantRole.resolve(
            name = "Anonymous Creator",
            isGuest = false,
            isAnonymousCreator = true,
            workAuthors = listOf("Someone Else")
        )
        assertEquals(AO3CommentParticipantRole.Author, role)
    }

    @Test
    fun guestNeverBecomesAuthorViaDisplayName() {
        val role = AO3CommentParticipantRole.resolve(
            name = "Work Author",
            isGuest = true,
            workAuthors = listOf("Work Author"),
            workAuthorUsernames = listOf("workauthor")
        )
        assertEquals(AO3CommentParticipantRole.Guest, role)
    }

    @Test
    fun usernameMatchIsAuthoritativeOverSharedPseudName() {
        val asAuthor = AO3CommentParticipantRole.resolve(
            name = "Shared Pseud",
            isGuest = false,
            commenterUsername = "author_acct",
            workAuthors = listOf("Shared Pseud"),
            workAuthorUsernames = listOf("author_acct")
        )
        val asUser = AO3CommentParticipantRole.resolve(
            name = "Shared Pseud",
            isGuest = false,
            commenterUsername = "other_acct",
            workAuthors = listOf("Shared Pseud"),
            workAuthorUsernames = listOf("author_acct")
        )
        assertEquals(AO3CommentParticipantRole.Author, asAuthor)
        assertEquals(AO3CommentParticipantRole.User, asUser)
    }

    @Test
    fun displayNameFallbackWhenNoCommenterUsername() {
        val role = AO3CommentParticipantRole.resolve(
            name = "Work Author",
            isGuest = false,
            commenterUsername = null,
            workAuthors = listOf("Work Author"),
            workAuthorUsernames = emptyList()
        )
        assertEquals(AO3CommentParticipantRole.Author, role)
    }

    @Test
    fun registeredNonAuthorIsUser() {
        val role = AO3CommentParticipantRole.resolve(
            name = "Random Reader",
            isGuest = false,
            commenterUsername = "reader",
            currentUsername = "someone_else",
            workAuthors = listOf("Work Author"),
            workAuthorUsernames = listOf("workauthor")
        )
        assertEquals(AO3CommentParticipantRole.User, role)
    }

    @Test
    fun defaultAo3SkinIconIsRejected() {
        assertTrue(
            AO3CommentAvatar.isDefaultAO3Icon(
                "https://archiveofourown.org/images/skins/iconsets/default/icon_user.png"
            )
        )
        assertNull(
            AO3CommentAvatar.avatarUrlForIconSource(
                "/images/skins/iconsets/default/icon_user.png"
            )
        )
    }

    @Test
    fun realUserIconIsAccepted() {
        val url = AO3CommentAvatar.avatarUrlForIconSource("/images/icons/AO3_Reader.png")
        assertEquals("https://archiveofourown.org/images/icons/AO3_Reader.png", url)
        assertFalse(AO3CommentAvatar.isDefaultAO3Icon(url!!))
    }

    @Test
    fun usernameFromProfilePath() {
        assertEquals(
            "AO3_Reader",
            AO3CommentAvatar.usernameFromProfilePath("/users/AO3_Reader/pseuds/AO3_Reader")
        )
        assertEquals(
            "WorkAuthor",
            AO3CommentAvatar.usernameFromProfilePath(
                "https://archiveofourown.org/users/WorkAuthor"
            )
        )
        assertNull(AO3CommentAvatar.usernameFromProfilePath("/users/login"))
        assertNull(AO3CommentAvatar.usernameFromProfilePath(null))
    }
}
