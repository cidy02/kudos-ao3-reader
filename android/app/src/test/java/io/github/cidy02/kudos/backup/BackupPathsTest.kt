package io.github.cidy02.kudos.backup

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupPathsTest {

    /**
     * [BackupPaths.uniqueSuffixedFontFileName] is a tight CPU loop with no
     * coroutine suspension points, so [kotlinx.coroutines.withTimeout] cannot
     * interrupt a hang. [Thread.join] has a real timeout; asserting the
     * worker is no longer alive then fails the test instead of hanging the
     * suite.
     */
    private fun <T> runOnWorkerWithJoinTimeout(timeoutMillis: Long = 1_000L, block: () -> T): T {
        val error = arrayOfNulls<Throwable>(1)
        val result = arrayOfNulls<Any>(1)
        val worker = Thread(
            {
                try {
                    result[0] = block()
                } catch (thrown: Throwable) {
                    error[0] = thrown
                }
            },
            "uniqueSuffixedFontFileName-bound"
        )
        worker.isDaemon = true
        worker.start()
        worker.join(timeoutMillis)
        assertFalse(
            "uniqueSuffixedFontFileName did not finish within ${timeoutMillis}ms (still spinning)",
            worker.isAlive
        )
        error[0]?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return result[0] as T
    }

    private fun assertUniqueSafeFontFileName(original: String, result: String, existing: Set<String>) {
        assertTrue(result.length <= BackupPaths.MAX_FONT_FILE_NAME_LENGTH)
        assertTrue(BackupPaths.isSafeFontFileName(result))
        assertNotEquals(original, result)
        val foldedExisting = existing.mapTo(mutableSetOf()) { BackupPaths.fontFileNameKey(it) }
        assertFalse(BackupPaths.fontFileNameKey(result) in foldedExisting)
    }

    @Test
    fun testUniqueSuffixedFontFileName_lengthLimits() {
        // Base lengths 117, 118, 128
        val base117 = "a".repeat(117)
        val name117 = "$base117.ttf"

        val base118 = "b".repeat(118)
        val name118 = "$base118.ttf"

        val base128 = "c".repeat(128)
        val name128 = base128

        // One character, a dot, then 120 characters: the extension alone
        // plus `-restored-1` exceeds the cap unless the extension is truncated.
        val namePathological = "d." + "e".repeat(120)

        val existing = setOf(name117, name118, name128, namePathological)

        runOnWorkerWithJoinTimeout {
            val res117 = BackupPaths.uniqueSuffixedFontFileName(name117, existing)
            assertUniqueSafeFontFileName(name117, res117, existing)

            val res118 = BackupPaths.uniqueSuffixedFontFileName(name118, existing)
            assertUniqueSafeFontFileName(name118, res118, existing)

            val res128 = BackupPaths.uniqueSuffixedFontFileName(name128, existing)
            assertUniqueSafeFontFileName(name128, res128, existing)

            val resPathological = BackupPaths.uniqueSuffixedFontFileName(namePathological, existing)
            assertUniqueSafeFontFileName(namePathological, resPathological, existing)
        }
    }
}
