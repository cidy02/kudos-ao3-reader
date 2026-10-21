package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.files.CacheStaging
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EpubPackageCacheTest {
    @Test
    fun unreadablePackageIsStagedInTheCacheAndDeletedWhenTheReadFails() {
        val cache = Files.createTempDirectory("epub-package-cache").toFile()
        val seen = mutableListOf<File>()
        val readable = CacheStaging.captureInto(seen) {
            EpubImportMetadata.isReadablePackage(byteArrayOf(1, 2, 3, 4), cache)
        }
        assertFalse(readable)
        val staged = seen.single()
        assertEquals(cache.canonicalFile, staged.parentFile.canonicalFile)
        assertFalse(staged.exists())
        assertTrue(cache.list().isNullOrEmpty())
    }
}
