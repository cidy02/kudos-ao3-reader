package io.github.cidy02.kudos.backup

import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A Replace may say "not replaced" only when every file went back (A53 F1). */
class BackupFileUndoTest {
    @Test fun aFileThatCannotBePutBackLeavesTheUndoIncomplete() {
        val dir = Files.createTempDirectory("undo")
        val replaced = dir.resolve("a.epub").also { Files.write(it, byteArrayOf(1)) }
        val created = dir.resolve("b.epub")
        val undo = BackupFileUndo()
        undo.beforeWrite(replaced)
        Files.write(replaced, byteArrayOf(2))
        undo.beforeWrite(created)
        // Something in the way of deleting the new file: a non-empty directory.
        Files.createDirectories(created.resolve("blocked")).also { Files.write(it.resolve("x"), byteArrayOf(0)) }

        undo.rollback(IOException("late failure"))

        assertFalse(undo.isUndone)
        assertArrayEquals(byteArrayOf(1), Files.readAllBytes(replaced))
    }

    @Test fun aCleanRollbackIsUndone() {
        val dir = Files.createTempDirectory("undo")
        val replaced = dir.resolve("a.epub").also { Files.write(it, byteArrayOf(1)) }
        val undo = BackupFileUndo()
        undo.beforeWrite(replaced)
        Files.write(replaced, byteArrayOf(2))

        undo.rollback(IOException("late failure"))

        assertTrue(undo.isUndone)
        assertArrayEquals(byteArrayOf(1), Files.readAllBytes(replaced))
    }
}
