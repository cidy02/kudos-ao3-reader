package io.github.cidy02.kudos.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppVersionTest {
    @Test
    fun `parses bare semver`() {
        assertEquals(AppVersion(0, 1, 0), AppVersion.parse("0.1.0"))
    }

    @Test
    fun `parses v-prefixed tag`() {
        assertEquals(AppVersion(1, 2, 3), AppVersion.parse("v1.2.3"))
    }

    @Test
    fun `parses android release tag with channel suffix`() {
        assertEquals(AppVersion(0, 1, 0), AppVersion.parse("android-v0.1.0-alpha"))
    }

    @Test
    fun `returns null for unparsable text`() {
        assertNull(AppVersion.parse("sideload-test-20260706-1050"))
        assertNull(AppVersion.parse("ios-test-build-20260703-e8a6164"))
    }

    @Test
    fun `compares numerically, not lexicographically`() {
        assertTrue(AppVersion(0, 10, 0) > AppVersion(0, 9, 0))
        assertTrue(AppVersion(1, 0, 0) > AppVersion(0, 99, 99))
        assertTrue(AppVersion(0, 1, 1) > AppVersion(0, 1, 0))
        assertEquals(AppVersion(0, 1, 0), AppVersion(0, 1, 0))
    }
}
