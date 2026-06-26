package io.github.cidy02.kudos.files

import java.nio.file.Files
import kotlin.io.path.exists
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkFileStoreTest {
    private val workId = "11111111-1111-1111-1111-111111111111"

    @Test
    fun writesDownloadedEpubToAppPrivateWorksDirectory() = runTest {
        val root = Files.createTempDirectory("kudos-files")
        val store = WorkFileStore(root)
        val bytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)

        val result = store.writeWorkEpub(workId, bytes)

        assertTrue(result is FileWriteResult.Success)
        val path = (result as FileWriteResult.Success).path
        assertTrue(path.toString().endsWith("works/$workId.epub"))
        assertArrayEquals(bytes, Files.readAllBytes(path))
        assertTrue(store.workEpubExists(workId))
    }

    @Test
    fun deleteLocalEpubRemovesOnlyTheFile() = runTest {
        val root = Files.createTempDirectory("kudos-files-delete")
        val store = WorkFileStore(root)
        store.writeWorkEpub(workId, byteArrayOf(0x50, 0x4B, 0x03, 0x04))

        assertTrue(store.deleteWorkEpub(workId))

        assertFalse(store.workEpubPath(workId).exists())
    }
}

class WorkFileStoreRejectsUnsafePathTest {
    @Test
    fun rejectsNonUuidWorkIds() {
        val store = WorkFileStore(Files.createTempDirectory("kudos-files-unsafe"))

        assertThrows(IllegalArgumentException::class.java) {
            store.workEpubPath("../not-a-uuid")
        }
    }
}
