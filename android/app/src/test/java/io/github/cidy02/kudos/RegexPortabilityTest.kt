package io.github.cidy02.kudos

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Android's regex engine (ICU) rejects Java's `(?U)` / UNICODE_CHARACTER_CLASS, which the JVM
 * these tests run on accepts: such a pattern passes here and crashes on a device. One did,
 * opening the comment composer (2026-10-16).
 */
class RegexPortabilityTest {
    @Test fun noPatternUsesAFlagAndroidRejects() {
        val root = listOf("src/main/java", "app/src/main/java", "android/app/src/main/java").map(::File).first(File::isDirectory)
        val offenders = root.walk().filter { it.extension == "kt" }.flatMap { file ->
            file.readLines().withIndex().filter { (_, line) -> "(?U)" in line || "UNICODE_CHARACTER_CLASS" in line }
                .map { (index, _) -> "${file.name}:${index + 1}" }
        }.toList()
        assertEquals(emptyList<String>(), offenders)
    }

    @Test fun commentBodiesNormaliseUnicodeWhitespace() {
        assertEquals("a b c", io.github.cidy02.kudos.network.ao3.comments.CommentSubmissionKey.normalize(" a \n\tb  c "))
    }
}
