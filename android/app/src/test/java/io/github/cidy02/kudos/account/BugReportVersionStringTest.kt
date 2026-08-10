package io.github.cidy02.kudos.account

import org.junit.Assert.assertEquals
import org.junit.Test

class BugReportVersionStringTest {
    @Test
    fun `includes short SHA when present — matches iOS shape`() {
        assertEquals(
            "0.2.0 (8) · a1b2c3d",
            bugReportVersionString(
                versionName = "0.2.0",
                versionCode = 8,
                gitCommitSha = "a1b2c3d"
            )
        )
    }

    @Test
    fun `omits SHA segment when empty or blank — no misleading placeholder`() {
        assertEquals(
            "0.2.0 (8)",
            bugReportVersionString(
                versionName = "0.2.0",
                versionCode = 8,
                gitCommitSha = ""
            )
        )
        assertEquals(
            "0.2.0 (8)",
            bugReportVersionString(
                versionName = "0.2.0",
                versionCode = 8,
                gitCommitSha = "   "
            )
        )
    }

    @Test
    fun `trims surrounding whitespace on SHA`() {
        assertEquals(
            "1.0 (1) · deadbee",
            bugReportVersionString(
                versionName = "1.0",
                versionCode = 1,
                gitCommitSha = "  deadbee\n"
            )
        )
    }
}
